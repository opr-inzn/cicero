import Accelerate
import CoreML
import CoreText
import Foundation
import Synchronization

public final class LetterEmbedding: Sendable {
    private let url: URL
    private let model = Mutex(Model.unloaded)

    private enum Model {
        case unloaded
        case loaded(MLModel)
        case failed
    }

    public static let dimensions = 128
    public static let classifications: [Classification] = [.serif, .sansSerif, .script, .ornamental]

    public struct Reading: Equatable, Sendable {
        public var embedding: [Float]
        public var classification: [Float]?
    }

    public init?(contentsOf url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        self.url = url
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
        model.withLock { if case .failed = $0 { true } else { false } }
    }

    public func read(_ font: CTFont) -> Reading? {
        if case .read(let reading) = outcome(font) { return reading }
        return nil
    }

    func outcome(_ font: CTFont) -> Outcome {
        let inputs = model.withLock { state -> (strips: Bool, details: Bool)? in
            if case .unloaded = state { state = (try? MLModel(contentsOf: url)).map(Model.loaded) ?? .failed }
            guard case .loaded(let model) = state else { return nil }
            let inputs = model.modelDescription.inputDescriptionsByName
            return (inputs["strips"] != nil, inputs["details"] != nil)
        }
        guard let (takesStrips, takesDetails) = inputs else { return .failed }
        guard let drawn = LetterImages.draw(font, strips: takesStrips, details: takesDetails) else { return .undrawable }
        var letters = [Float](repeating: 0, count: drawn.pixels.count)
        vDSP.convertElements(of: drawn.pixels, to: &letters)
        letters = vDSP.divide(letters, 255)
        var lines = [Float](repeating: 0, count: drawn.strips.count)
        vDSP.convertElements(of: drawn.strips, to: &lines)
        lines = vDSP.divide(lines, 255)
        var large = [Float](repeating: 0, count: drawn.details.count)
        vDSP.convertElements(of: drawn.details, to: &large)
        large = vDSP.divide(large, 255)
        let found = model.withLock { state -> Reading? in
            guard case .loaded(let model) = state else { return nil }
            let shape = [1, LetterImages.letters.count, LetterImages.size, LetterImages.size] as [NSNumber]
            guard let input = try? MLMultiArray(shape: shape, dataType: .float32),
                  let advances = try? MLMultiArray(shape: [1, LetterImages.letters.count] as [NSNumber], dataType: .float32)
            else { return nil }
            input.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in _ = buffer.update(from: letters) }
            advances.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in _ = buffer.update(from: drawn.advances) }
            var inputs: [String: Any] = ["letters": input]
            if model.modelDescription.inputDescriptionsByName["advances"] != nil { inputs["advances"] = advances }
            if takesStrips {
                let shape = [1, LetterImages.words.count, LetterImages.size, LetterImages.stripWidth] as [NSNumber]
                guard let strips = try? MLMultiArray(shape: shape, dataType: .float32) else { return nil }
                strips.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in _ = buffer.update(from: lines) }
                inputs["strips"] = strips
            }
            if takesDetails {
                let shape = [1, LetterImages.detailLetters.count, LetterImages.detailSize, LetterImages.detailSize] as [NSNumber]
                guard let details = try? MLMultiArray(shape: shape, dataType: .float32) else { return nil }
                details.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in _ = buffer.update(from: large) }
                inputs["details"] = details
            }
            guard let features = try? MLDictionaryFeatureProvider(dictionary: inputs),
                  let output = try? model.prediction(from: features),
                  let embedding = output.featureValue(for: "embedding")?.multiArrayValue.map(Self.values)
            else { return nil }
            return Reading(embedding: embedding, classification: output.featureValue(for: "classification")?.multiArrayValue.map(Self.values))
        }
        guard var reading = found, reading.embedding.count == Self.dimensions, reading.embedding.allSatisfy(\.isFinite) else { return .failed }
        if let classification = reading.classification, classification.count != Self.classifications.count || !classification.allSatisfy(\.isFinite) {
            reading.classification = nil
        }
        return .read(reading)
    }

    private static func values(_ array: MLMultiArray) -> [Float] {
        array.dataType == .float32
            ? array.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
            : (0..<array.count).map { array[$0].floatValue }
    }
}
