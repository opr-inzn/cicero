import Accelerate
import CoreML
import CoreText
import Foundation
import Synchronization

/// What a face's letters look like as `dimensions` numbers, from a small model that learned it from Google Fonts'
/// families (scripts/embedding): it looks at the letters as `LetterImages` draws them, and faces that look alike,
/// scripts, stencils and outlines too, come out close together. The numbers have a length of 1, so two faces are
/// 0 apart when alike and up to 2 when not. Next to the letter measurements in `SimilarFonts`.
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

    /// The compiled model (LetterEmbedding.mlmodelc); nil when there's none.
    public init?(contentsOf url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        self.url = url
    }

    /// nil for a face with too few of the letters, as `LetterImages` says, and when the model can't be loaded.
    public func embedding(of font: CTFont) -> [Float]? {
        guard let pixels = LetterImages.draw(font) else { return nil }
        var letters = [Float](repeating: 0, count: pixels.count)
        vDSP.convertElements(of: pixels, to: &letters)
        letters = vDSP.divide(letters, 255)
        let found = model.withLock { state -> [Float]? in
            if case .unloaded = state { state = (try? MLModel(contentsOf: url)).map(Model.loaded) ?? .failed }
            guard case .loaded(let model) = state else { return nil }
            let shape = [1, LetterImages.letters.count, LetterImages.size, LetterImages.size] as [NSNumber]
            guard let input = try? MLMultiArray(shape: shape, dataType: .float32) else { return nil }
            input.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in _ = buffer.update(from: letters) }
            guard let features = try? MLDictionaryFeatureProvider(dictionary: ["letters": input]),
                  let output = try? model.prediction(from: features),
                  let embedding = output.featureValue(for: "embedding")?.multiArrayValue
            else { return nil }
            return embedding.dataType == .float32
                ? embedding.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
                : (0..<embedding.count).map { embedding[$0].floatValue }
        }
        guard let values = found else { return nil }
        return values.count == Self.dimensions && values.allSatisfy(\.isFinite) ? values : nil
    }
}
