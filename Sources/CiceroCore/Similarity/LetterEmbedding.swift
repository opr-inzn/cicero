import Accelerate
import CoreML
import CoreText
import Foundation
import Synchronization

public final class LetterEmbedding: Sendable {
    private let url: URL
    private let state = Mutex(ModelState.unloaded)
    private let loadQueue = DispatchQueue(label: "Cicero.LetterEmbedding.load", qos: .utility)
    private let loadedTagNames = Mutex<[String]?>(nil)

    private struct LoadedModel: @unchecked Sendable {
        let model: MLModel
        let takesStrips: Bool
        let takesDetails: Bool
        let takesAdvances: Bool
        let letterCount: Int
        let tagNames: [String]
    }

    private enum ModelState: Sendable {
        case unloaded
        case loaded(LoadedModel)
        case failed
    }

    public static let dimensions = 128
    public static let classifications: [Classification] = [.serif, .sansSerif, .script, .ornamental]

    public struct Reading: Equatable, Sendable {
        public var embedding: [Float]
        public var classification: [Float]?
        public var tags: [Float]?
    }

    public init?(contentsOf url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        self.url = url
    }

    public var tagNames: [String] {
        if let names = loadedTagNames.withLock({ $0 }) { return names }
        return loadedModel()?.tagNames ?? []
    }

    public func embedding(of font: CTFont) -> [Float]? {
        read(font)?.embedding
    }

    enum Outcome {
        case read(Reading)
        case undrawable
        case failed
    }

    var hasFailed: Bool {
        state.withLock { if case .failed = $0 { true } else { false } }
    }

    public func prepare() async {
        if case .unloaded = state.withLock({ $0 }) {} else { return }
        await withCheckedContinuation { continuation in
            loadQueue.async {
                _ = self.loadOnQueue()
                continuation.resume()
            }
        }
    }

    public func unload(if shouldUnload: @escaping @Sendable () -> Bool = { true }) {
        loadQueue.async {
            guard shouldUnload() else { return }
            self.state.withLock { if case .loaded = $0 { $0 = .unloaded } }
        }
    }

    public func read(_ font: CTFont, glyphMap: ((Character) -> CGGlyph?)? = nil) -> Reading? {
        if case .read(let reading) = outcome(font, glyphMap: glyphMap) { return reading }
        return nil
    }

    private func loadOnQueue() -> LoadedModel? {
        switch state.withLock({ $0 }) {
        case .loaded(let loaded): return loaded
        case .failed: return nil
        case .unloaded: break
        }
        guard let mlModel = try? MLModel(contentsOf: url) else {
            state.withLock { $0 = .failed }
            return nil
        }
        let inputs = mlModel.modelDescription.inputDescriptionsByName
        let meta = mlModel.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        let loaded = LoadedModel(model: mlModel, takesStrips: inputs["strips"] != nil,
                                 takesDetails: inputs["details"] != nil, takesAdvances: inputs["advances"] != nil,
                                 letterCount: inputs["letters"]?.multiArrayConstraint?.shape[1].intValue ?? LetterImages.letters.count,
                                 tagNames: (meta?["tags"]).map { $0.split(separator: ",").map(String.init) } ?? [])
        state.withLock { $0 = .loaded(loaded) }
        loadedTagNames.withLock { $0 = loaded.tagNames }
        return loaded
    }

    private func loadedModel() -> LoadedModel? {
        switch state.withLock({ $0 }) {
        case .loaded(let loaded): return loaded
        case .failed: return nil
        case .unloaded: break
        }
        return loadQueue.sync { loadOnQueue() }
    }

    func outcome(_ font: CTFont, glyphMap: ((Character) -> CGGlyph?)? = nil) -> Outcome {
        guard let loaded = loadedModel() else { return .failed }
        guard let drawn = LetterImages.draw(font, strips: loaded.takesStrips, details: loaded.takesDetails, glyphMap: glyphMap) else { return .undrawable }
        let usableLetters = min(loaded.letterCount, LetterImages.letters.count)
        let pixelCount = usableLetters * LetterImages.size * LetterImages.size
        var letters = [Float](repeating: 0, count: pixelCount)
        vDSP.convertElements(of: drawn.pixels.prefix(pixelCount), to: &letters)
        letters = vDSP.divide(letters, 255)
        var lines = [Float](repeating: 0, count: drawn.strips.count)
        vDSP.convertElements(of: drawn.strips, to: &lines)
        lines = vDSP.divide(lines, 255)
        var large = [Float](repeating: 0, count: drawn.details.count)
        vDSP.convertElements(of: drawn.details, to: &large)
        large = vDSP.divide(large, 255)
        let shape = [1, usableLetters, LetterImages.size, LetterImages.size] as [NSNumber]
        guard let input = try? MLMultiArray(shape: shape, dataType: .float32),
              let advances = try? MLMultiArray(shape: [1, usableLetters] as [NSNumber], dataType: .float32)
        else { return .failed }
        input.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in _ = buffer.update(from: letters) }
        advances.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in _ = buffer.update(from: drawn.advances.prefix(usableLetters)) }
        var inputs: [String: Any] = ["letters": input]
        if loaded.takesAdvances { inputs["advances"] = advances }
        if loaded.takesStrips {
            let shape = [1, LetterImages.words.count, LetterImages.size, LetterImages.stripWidth] as [NSNumber]
            guard let strips = try? MLMultiArray(shape: shape, dataType: .float32) else { return .failed }
            strips.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in _ = buffer.update(from: lines) }
            inputs["strips"] = strips
        }
        if loaded.takesDetails {
            let shape = [1, LetterImages.detailLetters.count, LetterImages.detailSize, LetterImages.detailSize] as [NSNumber]
            guard let details = try? MLMultiArray(shape: shape, dataType: .float32) else { return .failed }
            details.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in _ = buffer.update(from: large) }
            inputs["details"] = details
        }
        guard let features = try? MLDictionaryFeatureProvider(dictionary: inputs),
              let output = try? loaded.model.prediction(from: features),
              let embedding = output.featureValue(for: "embedding")?.multiArrayValue.map(Self.values)
        else { return .failed }
        var reading = Reading(
            embedding: embedding,
            classification: output.featureValue(for: "classification")?.multiArrayValue.map(Self.values),
            tags: output.featureValue(for: "tags")?.multiArrayValue.map(Self.values)
        )
        guard reading.embedding.count == Self.dimensions, reading.embedding.allSatisfy(\.isFinite) else { return .failed }
        if let classification = reading.classification, classification.count != Self.classifications.count || !classification.allSatisfy(\.isFinite) {
            reading.classification = nil
        }
        if let tags = reading.tags, tags.isEmpty || !tags.allSatisfy(\.isFinite) {
            reading.tags = nil
        }
        return .read(reading)
    }

    private static func values(_ array: MLMultiArray) -> [Float] {
        array.dataType == .float32
            ? array.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
            : (0..<array.count).map { array[$0].floatValue }
    }
}
