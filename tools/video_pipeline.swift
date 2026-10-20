import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func saveCGImage(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "VideoPipeline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        throw NSError(domain: "VideoPipeline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG"])
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: video_pipeline <inspect|extract|compose> ...\n", stderr)
    exit(1)
}

let cmd = args[1]
let sem = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0

Task {
    do {
        if cmd == "inspect" {
            let url = URL(fileURLWithPath: args[2])
            let asset = AVURLAsset(url: url)
            let dur = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let vt = tracks.first else {
                throw NSError(domain: "VideoPipeline", code: 3, userInfo: [NSLocalizedDescriptionKey: "No video track"])
            }
            let size = try await vt.load(.naturalSize)
            let fps = try await vt.load(.nominalFrameRate)
            let info: [String: Any] = [
                "path": args[2],
                "duration": CMTimeGetSeconds(dur),
                "width": Int(abs(size.width)),
                "height": Int(abs(size.height)),
                "fps": fps
            ]
            let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted])
            print(String(data: data, encoding: .utf8)!)
        } else if cmd == "extract" {
            // video_pipeline extract <video.mp4> <out_dir> <step_seconds>
            let url = URL(fileURLWithPath: args[2])
            let outDir = URL(fileURLWithPath: args[3])
            let step = Double(args[4]) ?? 0.5
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let asset = AVURLAsset(url: url)
            let dur = CMTimeGetSeconds(try await asset.load(.duration))
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            var t = 0.0
            var idx = 0
            while t < dur - 0.01 {
                let cm = CMTime(seconds: t, preferredTimescale: 600)
                let (cgImg, _) = try await gen.image(at: cm)
                let fname = String(format: "frame_%03d_t%05.2f.png", idx, t)
                try saveCGImage(cgImg, to: outDir.appendingPathComponent(fname))
                idx += 1
                t += step
            }
            print("Extracted \(idx) exact frames from \(args[2]) (duration=\(String(format: "%.3f", dur))s)")
        } else if cmd == "compose" {
            // video_pipeline compose <out.mp4> <clip1> <clip2> <clip3> <clip4>
            // Builds an exact 20.000s seamless-looping 1280x720 30fps MP4 with exact cross-dissolves at:
            //   Act 1: [0.00, 5.00) using clip1[lead .. lead+5.00]
            //   Dissolve 1->2 over [4.40, 5.00] (0.60s)
            //   Act 2: [5.00, 10.00) using clip2[0.60 .. 5.60]
            //   Dissolve 2->3 over [9.40, 10.00] (0.60s)
            //   Act 3: [10.00, 15.00) using clip3[0.60 .. 5.60]
            //   Dissolve 3->4 over [14.40, 15.00] (0.60s)
            //   Act 4: [15.00, 20.00) using clip4[0.60 .. 5.60]
            //   Seamless Loop Wrap over [19.40, 20.00] into clip1[0.00 .. 0.60] -> matches t=0.00 (clip1[0.60]) continuously!
            let outURL = URL(fileURLWithPath: args[2])
            try? FileManager.default.removeItem(at: outURL)
            let clipPaths = Array(args[3..<7])
            let comp = AVMutableComposition()
            let renderSize = CGSize(width: 1280, height: 720)
            let timescale: CMTimeScale = 600
            let fade: Double = 0.60
            let actDur: Double = 5.00
            let totalDur: Double = 20.00

            struct Seg {
                let track: AVMutableCompositionTrack
                let naturalSize: CGSize
                let transform: CGAffineTransform
                let fadeInStart: Double?
                let fadeInEnd: Double?
                let zOrder: Int
            }
            var segs: [Seg] = []

            var assets: [AVURLAsset] = []
            var vTracks: [AVAssetTrack] = []
            var durs: [Double] = []
            for p in clipPaths {
                let a = AVURLAsset(url: URL(fileURLWithPath: p))
                let d = CMTimeGetSeconds(try await a.load(.duration))
                guard let vt = try await a.loadTracks(withMediaType: .video).first else {
                    throw NSError(domain: "VideoPipeline", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing video track in \(p)"])
                }
                assets.append(a)
                vTracks.append(vt)
                durs.append(d)
                print("Loaded \(p): duration=\(String(format: "%.3f", d))s")
            }

            func makeFitTransform(_ vt: AVAssetTrack) async throws -> (CGSize, CGAffineTransform) {
                let ns = try await vt.load(.naturalSize)
                let pref = try await vt.load(.preferredTransform)
                let rect = CGRect(origin: .zero, size: ns).applying(pref)
                let w = abs(rect.width), h = abs(rect.height)
                let scale = max(renderSize.width / w, renderSize.height / h)
                let tx = (renderSize.width - w * scale) * 0.5 - rect.minX * scale
                let ty = (renderSize.height - h * scale) * 0.5 - rect.minY * scale
                return (CGSize(width: w, height: h), pref.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: tx, y: ty)))
            }

            // Track A0: Act 1 main [0.00 .. 5.00] from clip1[fade .. fade + 5.00] (or scaled rate if clip < 5.6s)
            for i in 0..<4 {
                let vt = vTracks[i]
                let (_, tf) = try await makeFitTransform(vt)
                let needed = actDur + fade
                let avail = durs[i]

                if i == 0 {
                    // Main body of Act 1 at [0.00, 5.00]
                    guard let trMain = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                    let srcStart = min(fade, avail * 0.1)
                    let srcLen = min(actDur, avail - srcStart)
                    try trMain.insertTimeRange(
                        CMTimeRange(start: CMTime(seconds: srcStart, preferredTimescale: timescale),
                                    duration: CMTime(seconds: srcLen, preferredTimescale: timescale)),
                        of: vt,
                        at: .zero
                    )
                    if srcLen < actDur {
                        trMain.scaleTimeRange(
                            CMTimeRange(start: .zero, duration: CMTime(seconds: srcLen, preferredTimescale: timescale)),
                            toDuration: CMTime(seconds: actDur, preferredTimescale: timescale)
                        )
                    }
                    segs.append(Seg(track: trMain, naturalSize: renderSize, transform: tf, fadeInStart: nil, fadeInEnd: nil, zOrder: 1))

                    // Seamless wrap tail at [19.40, 20.00] using clip1[0.00 .. srcStart] scaled to 0.60s!
                    guard let trWrap = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                    let wrapSrc = max(srcStart, 0.2)
                    try trWrap.insertTimeRange(
                        CMTimeRange(start: .zero, duration: CMTime(seconds: wrapSrc, preferredTimescale: timescale)),
                        of: vt,
                        at: CMTime(seconds: totalDur - fade, preferredTimescale: timescale)
                    )
                    trWrap.scaleTimeRange(
                        CMTimeRange(start: CMTime(seconds: totalDur - fade, preferredTimescale: timescale),
                                    duration: CMTime(seconds: wrapSrc, preferredTimescale: timescale)),
                        toDuration: CMTime(seconds: fade, preferredTimescale: timescale)
                    )
                    segs.append(Seg(track: trWrap, naturalSize: renderSize, transform: tf, fadeInStart: totalDur - fade, fadeInEnd: totalDur, zOrder: 10))
                } else {
                    // Act i+1 starts fading in at (i * 5.0 - fade) and runs until ((i+1) * 5.0) => total duration 5.60s
                    guard let tr = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                    let destStart = Double(i) * actDur - fade
                    let srcLen = min(needed, avail)
                    try tr.insertTimeRange(
                        CMTimeRange(start: .zero, duration: CMTime(seconds: srcLen, preferredTimescale: timescale)),
                        of: vt,
                        at: CMTime(seconds: destStart, preferredTimescale: timescale)
                    )
                    if abs(srcLen - needed) > 0.001 {
                        tr.scaleTimeRange(
                            CMTimeRange(start: CMTime(seconds: destStart, preferredTimescale: timescale),
                                        duration: CMTime(seconds: srcLen, preferredTimescale: timescale)),
                            toDuration: CMTime(seconds: needed, preferredTimescale: timescale)
                        )
                    }
                    segs.append(Seg(track: tr, naturalSize: renderSize, transform: tf, fadeInStart: destStart, fadeInEnd: destStart + fade, zOrder: i + 2))
                }
            }

            // Sort high zOrder FIRST so top layers render in front in AVVideoCompositionInstruction.layerInstructions!
            let sortedSegs = segs.sorted { $0.zOrder > $1.zOrder }
            let layerInstructions: [AVVideoCompositionLayerInstruction] = sortedSegs.map { s in
                let li = AVMutableVideoCompositionLayerInstruction(assetTrack: s.track)
                li.setTransform(s.transform, at: .zero)
                if let fs = s.fadeInStart, let fe = s.fadeInEnd {
                    li.setOpacity(0.0, at: .zero)
                    li.setOpacityRamp(
                        fromStartOpacity: 0.0,
                        toEndOpacity: 1.0,
                        timeRange: CMTimeRange(
                            start: CMTime(seconds: fs, preferredTimescale: timescale),
                            duration: CMTime(seconds: fe - fs, preferredTimescale: timescale)
                        )
                    )
                }
                return li
            }

            let instr = AVMutableVideoCompositionInstruction()
            instr.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: totalDur, preferredTimescale: timescale))
            instr.layerInstructions = layerInstructions

            let vcomp = AVMutableVideoComposition()
            vcomp.renderSize = renderSize
            vcomp.frameDuration = CMTime(value: 1, timescale: 30)
            vcomp.instructions = [instr]

            guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
                throw NSError(domain: "VideoPipeline", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
            }
            export.videoComposition = vcomp
            export.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: totalDur, preferredTimescale: timescale))
            try await export.export(to: outURL, as: .mp4)
            print("Successfully exported seamless 20.000s film to \(outURL.path)")
        }
    } catch {
        fputs("Error: \(error)\n", stderr)
        exitCode = 1
    }
    sem.signal()
}

sem.wait()
exit(exitCode)
