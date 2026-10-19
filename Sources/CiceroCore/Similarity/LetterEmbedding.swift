import Accelerate
import CoreML
import CoreText
import Foundation
import Synchronization

/// What a face's letters look like as `dimensions` numbers, from a small model that learned it from Google Fonts'
/// families (scripts/embedding): it looks at the letters and their advances as `LetterImages` draws them, and faces
/// that look alike, scripts, stencils and outlines too, come out close together. The numbers have a length of 1, so
/// two faces are 0 apart when alike and up to 2 when not. Next to the letter measurements in `SimilarFonts`. The model also says
/// which of `classifications` the face is likely to be, for the families nothing in their files classifies.
public final class LetterEmbedding: Sendable {
    private let url: URL
    /// Loaded when first asked, which takes a fifth of a second, so in the background; it answers one question at a
    /// time here.
    private let model = Mutex(Model.unloaded)

    private enum Model {
        case unloaded
        case loaded(MLModel)
        case failed
    }

    public static let dimensions = 128
    /// The classifications the model tells apart, in the order of its answer. Monospaced faces it leaves to their
    /// advances, and symbol fonts haven't the letters.
    public static let classifications: [Classification] = [.serif, .sansSerif, .script, .ornamental]

    /// What the model says of a face.
    public struct Reading: Equatable, Sendable {
        public var embedding: [Float]
        /// How likely each of `classifications` is, adding up to 1; nil from a model that doesn't say.
        public var classification: [Float]?
    }

    /// The compiled model (LetterEmbedding.mlmodelc); nil when there's none.
    public init?(contentsOf url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        self.url = url
    }

    /// nil for a face with too few of the letters, as `LetterImages` says, and when the model can't be loaded.
    public func embedding(of font: CTFont) -> [Float]? {
        read(font)?.embedding
    }

    /// nil for a face with too few of the letters, as `LetterImages` says, and when the model can't be loaded.
    public func read(_ font: CTFont) -> Reading? {
        guard let drawn = LetterImages.draw(font) else { return nil }
        var letters = [Float](repeating: 0, count: drawn.pixels.count)
        vDSP.convertElements(of: drawn.pixels, to: &letters)
        letters = vDSP.divide(letters, 255)
        let found = model.withLock { state -> Reading? in
            if case .unloaded = state { state = (try? MLModel(contentsOf: url)).map(Model.loaded) ?? .failed }
            guard case .loaded(let model) = state else { return nil }
            let shape = [1, LetterImages.letters.count, LetterImages.size, LetterImages.size] as [NSNumber]
            guard let input = try? MLMultiArray(shape: shape, dataType: .float32),
                  let advances = try? MLMultiArray(shape: [1, LetterImages.letters.count] as [NSNumber], dataType: .float32)
            else { return nil }
            input.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in _ = buffer.update(from: letters) }
            advances.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in _ = buffer.update(from: drawn.advances) }
            var inputs: [String: Any] = ["letters": input]
            if model.modelDescription.inputDescriptionsByName["advances"] != nil { inputs["advances"] = advances }
            guard let features = try? MLDictionaryFeatureProvider(dictionary: inputs),
                  let output = try? model.prediction(from: features),
                  let embedding = output.featureValue(for: "embedding")?.multiArrayValue.map(Self.values)
            else { return nil }
            return Reading(embedding: embedding, classification: output.featureValue(for: "classification")?.multiArrayValue.map(Self.values))
        }
        guard var reading = found, reading.embedding.count == Self.dimensions, reading.embedding.allSatisfy(\.isFinite) else { return nil }
        if let classification = reading.classification, classification.count != Self.classifications.count || !classification.allSatisfy(\.isFinite) {
            reading.classification = nil
        }
        return reading
    }

    private static func values(_ array: MLMultiArray) -> [Float] {
        array.dataType == .float32
            ? array.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
            : (0..<array.count).map { array[$0].floatValue }
    }
}
