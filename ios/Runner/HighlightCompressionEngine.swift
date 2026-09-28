// ios/Runner/HighlightCompressionEngine.swift
//
// iOS counterpart to android/app/src/main/kotlin/com/eleaguehub/app/
// HighlightCompressionEngine.kt -- implements the SAME wire contract the
// Dart side (lib/features/highlights/data/video_compression_service.dart)
// already hardcodes, so no Dart changes are needed for this to work:
//
//   MethodChannel "highlight_compression":
//     - "probe" { inputPath } -> { durationSeconds, width, height, format }
//     - "compress" { taskId, inputPath, outputPath, maxHeight,
//                     videoBitrateKbps, audioBitrateKbps }
//                   -> { outputPath, outputBytes, usedMaxHeight,
//                        usedVideoBitrateKbps, usedAudioBitrateKbps }
//   EventChannel "highlight_compression_progress":
//     emits { taskId, progress01 } best-effort.
//
// Unlike Android's Media3 Transformer (a single high-level call), iOS has
// no API that accepts an explicit target bitrate -- AVAssetExportSession
// only offers fixed named quality presets. Hitting the same "bitrate
// computed from a size/duration budget" policy the Dart layer already
// enforces requires the lower-level AVAssetReader -> AVAssetWriter
// pipeline used below: read decompressed samples, scale video via an
// AVVideoComposition's renderSize, re-encode H.264/AAC at the exact
// requested bitrates, write out.
//
// NOTE: this file cannot be compiled/tested in this environment (no
// macOS/Xcode toolchain here) -- it was written to well-established
// AVFoundation reader/writer patterns and reviewed carefully, but the
// first real CI build + a real device/TestFlight run is the actual test.

import AVFoundation
import Flutter
import Foundation

final class HighlightCompressionEngine: NSObject, FlutterStreamHandler {
    static let shared = HighlightCompressionEngine()

    private let queue = DispatchQueue(label: "com.eleaguehub.app.highlight_compression")
    private var progressSink: FlutterEventSink?
    private var busy = false
    private var activeTaskId: String?

    static func register(messenger: FlutterBinaryMessenger) {
        let methodChannel = FlutterMethodChannel(name: "highlight_compression", binaryMessenger: messenger)
        methodChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "probe":
                shared.handleProbe(call: call, result: result)
            case "compress":
                shared.handleCompress(call: call, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let progressChannel = FlutterEventChannel(name: "highlight_compression_progress", binaryMessenger: messenger)
        progressChannel.setStreamHandler(shared)
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        progressSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        progressSink = nil
        return nil
    }

    private func emitProgress(taskId: String, progress01: Double) {
        guard let sink = progressSink else { return }
        let p = max(0.0, min(1.0, progress01))
        DispatchQueue.main.async {
            sink(["taskId": taskId, "progress01": p])
        }
    }

    // MARK: - Input path handling

    // image_picker/file_picker on iOS return plain filesystem paths (iOS
    // has no content:// URI scheme, unlike Android), but tolerate a
    // file:// URL string too, defensively.
    private static func assetURL(for inputPath: String) -> URL {
        let trimmed = inputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            return url
        }
        return URL(fileURLWithPath: trimmed)
    }

    // MARK: - probe

    private func handleProbe(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let inputPath = (args["inputPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !inputPath.isEmpty else {
            result(FlutterError(code: "BAD_ARGS", message: "inputPath is required", details: nil))
            return
        }

        queue.async {
            let url = HighlightCompressionEngine.assetURL(for: inputPath)
            let asset = AVURLAsset(url: url)

            // Deliberately using the synchronous AVAsset properties (not the
            // newer async load(.duration)/load(.tracks) API) -- deprecated
            // on newer SDKs but still fully functional, and avoids adding
            // async/await control flow this file otherwise doesn't need.
            let durationSeconds = CMTimeGetSeconds(asset.duration)
            var width = 0
            var height = 0
            if let track = asset.tracks(withMediaType: .video).first {
                let size = track.naturalSize.applying(track.preferredTransform)
                width = Int(abs(size.width))
                height = Int(abs(size.height))
            }

            let response: [String: Any] = [
                "durationSeconds": durationSeconds.isFinite ? durationSeconds : 0.0,
                "width": max(0, width),
                "height": max(0, height),
                "format": "mp4",
            ]

            DispatchQueue.main.async {
                result(response)
            }
        }
    }

    // MARK: - compress

    private func handleCompress(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard busy == false else {
            result(FlutterError(code: "BUSY", message: "Compression is already running.", details: nil))
            return
        }

        guard let args = call.arguments as? [String: Any],
              let taskId = (args["taskId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !taskId.isEmpty,
              let inputPath = (args["inputPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !inputPath.isEmpty,
              let outputPath = (args["outputPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !outputPath.isEmpty
        else {
            result(FlutterError(code: "BAD_ARGS", message: "taskId, inputPath, outputPath are required", details: nil))
            return
        }

        let maxHeight = (args["maxHeight"] as? NSNumber)?.intValue ?? 720
        let videoBitrateKbps = (args["videoBitrateKbps"] as? NSNumber)?.intValue ?? 1500
        let audioBitrateKbps = (args["audioBitrateKbps"] as? NSNumber)?.intValue ?? 128

        busy = true
        activeTaskId = taskId
        emitProgress(taskId: taskId, progress01: 0)

        queue.async {
            self.runCompression(
                taskId: taskId,
                inputPath: inputPath,
                outputPath: outputPath,
                maxHeight: maxHeight,
                videoBitrateKbps: videoBitrateKbps,
                audioBitrateKbps: audioBitrateKbps
            ) { outcome in
                self.busy = false
                self.activeTaskId = nil
                DispatchQueue.main.async {
                    switch outcome {
                    case .success(let payload):
                        result(payload)
                    case .failure(let message):
                        result(FlutterError(code: "COMPRESS_FAILED", message: message, details: nil))
                    }
                }
            }
        }
    }

    private enum CompressOutcome {
        case success([String: Any])
        case failure(String)
    }

    private func runCompression(
        taskId: String,
        inputPath: String,
        outputPath: String,
        maxHeight: Int,
        videoBitrateKbps: Int,
        audioBitrateKbps: Int,
        completion: @escaping (CompressOutcome) -> Void
    ) {
        let inputURL = HighlightCompressionEngine.assetURL(for: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        // AVAssetWriter refuses to write to a path that already exists.
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVURLAsset(url: inputURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure("No video track found in input file."))
            return
        }

        let naturalSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        let inputWidth = abs(naturalSize.width)
        let inputHeight = abs(naturalSize.height)
        guard inputWidth > 0, inputHeight > 0 else {
            completion(.failure("Could not determine input video dimensions."))
            return
        }

        let clampedMaxHeight = CGFloat(max(240, min(maxHeight, 720)))
        let scale = min(1.0, clampedMaxHeight / inputHeight)
        // Even width/height -- H.264 encoders require this.
        var scaledWidth = Int((inputWidth * scale).rounded(.down))
        var scaledHeight = Int((inputHeight * scale).rounded(.down))
        if scaledWidth % 2 != 0 { scaledWidth -= 1 }
        if scaledHeight % 2 != 0 { scaledHeight -= 1 }
        scaledWidth = max(2, scaledWidth)
        scaledHeight = max(2, scaledHeight)

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            completion(.failure("Failed to initialize reader/writer: \(error.localizedDescription)"))
            return
        }

        // Video: read via a video-composition output so we can scale
        // during the pipeline (renderSize), rather than reading native-size
        // frames and resizing pixel buffers by hand.
        let videoComposition = AVMutableVideoComposition(propertiesOf: asset)
        videoComposition.renderSize = CGSize(width: scaledWidth, height: scaledHeight)

        let videoReaderOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: asset.tracks(withMediaType: .video),
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoReaderOutput.videoComposition = videoComposition
        guard reader.canAdd(videoReaderOutput) else {
            completion(.failure("Reader cannot accept video output."))
            return
        }
        reader.add(videoReaderOutput)

        let audioTrack = asset.tracks(withMediaType: .audio).first
        var audioReaderOutput: AVAssetReaderTrackOutput?
        if let audioTrack = audioTrack {
            let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            if reader.canAdd(out) {
                reader.add(out)
                audioReaderOutput = out
            }
        }

        let videoWriterSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: scaledWidth,
            AVVideoHeightKey: scaledHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitrateKbps * 1000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoWriterSettings)
        videoWriterInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoWriterInput) else {
            completion(.failure("Writer cannot accept video input."))
            return
        }
        writer.add(videoWriterInput)

        var audioWriterInput: AVAssetWriterInput?
        if audioReaderOutput != nil {
            let audioWriterSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: audioBitrateKbps * 1000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioWriterSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioWriterInput = input
            }
        }

        guard reader.startReading() else {
            completion(.failure("Failed to start reading: \(reader.error?.localizedDescription ?? "unknown")"))
            return
        }
        guard writer.startWriting() else {
            completion(.failure("Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")"))
            return
        }
        writer.startSession(atSourceTime: .zero)

        let totalDurationSeconds = CMTimeGetSeconds(asset.duration)
        let pumpGroup = DispatchGroup()

        pumpGroup.enter()
        let videoPumpQueue = DispatchQueue(label: "com.eleaguehub.app.highlight_compression.video")
        videoWriterInput.requestMediaDataWhenReady(on: videoPumpQueue) {
            while videoWriterInput.isReadyForMoreMediaData {
                if let sample = videoReaderOutput.copyNextSampleBuffer() {
                    if totalDurationSeconds > 0 {
                        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                        self.emitProgress(taskId: taskId, progress01: pts / totalDurationSeconds)
                    }
                    if !videoWriterInput.append(sample) {
                        break
                    }
                } else {
                    videoWriterInput.markAsFinished()
                    pumpGroup.leave()
                    break
                }
            }
        }

        if let audioReaderOutput = audioReaderOutput, let audioWriterInput = audioWriterInput {
            pumpGroup.enter()
            let audioPumpQueue = DispatchQueue(label: "com.eleaguehub.app.highlight_compression.audio")
            audioWriterInput.requestMediaDataWhenReady(on: audioPumpQueue) {
                while audioWriterInput.isReadyForMoreMediaData {
                    if let sample = audioReaderOutput.copyNextSampleBuffer() {
                        if !audioWriterInput.append(sample) {
                            break
                        }
                    } else {
                        audioWriterInput.markAsFinished()
                        pumpGroup.leave()
                        break
                    }
                }
            }
        }

        pumpGroup.notify(queue: queue) {
            if reader.status == .failed {
                writer.cancelWriting()
                completion(.failure("Reading failed: \(reader.error?.localizedDescription ?? "unknown")"))
                return
            }

            writer.finishWriting {
                if writer.status == .completed {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath)
                    let outputBytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                    if outputBytes <= 0 {
                        completion(.failure("Compression produced an empty file."))
                        return
                    }
                    self.emitProgress(taskId: taskId, progress01: 1.0)
                    completion(.success([
                        "outputPath": outputPath,
                        "outputBytes": outputBytes,
                        "usedMaxHeight": scaledHeight,
                        "usedVideoBitrateKbps": videoBitrateKbps,
                        "usedAudioBitrateKbps": audioBitrateKbps,
                    ]))
                } else {
                    try? FileManager.default.removeItem(at: outputURL)
                    completion(.failure("Writing failed: \(writer.error?.localizedDescription ?? "unknown")"))
                }
            }
        }
    }
}
