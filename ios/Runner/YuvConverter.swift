import Flutter
import UIKit

class YuvConverter {
    static let CHANNEL = "bowling_diary/yuv_converter"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { call, result in
            if call.method == "convert" {
                guard let args = call.arguments as? [String: Any],
                      let width = args["width"] as? Int,
                      let height = args["height"] as? Int,
                      let yData = (args["yPlane"] as? FlutterStandardTypedData)?.data,
                      let uData = (args["uPlane"] as? FlutterStandardTypedData)?.data,
                      let vData = (args["vPlane"] as? FlutterStandardTypedData)?.data,
                      let yRowStride = args["yRowStride"] as? Int,
                      let uvRowStride = args["uvRowStride"] as? Int,
                      let uvPixelStride = args["uvPixelStride"] as? Int
                else {
                    result(FlutterError(code: "BAD_ARGS", message: "missing args", details: nil))
                    return
                }
                let rgba = convertYuvToRgba(
                    width: width, height: height,
                    y: yData, u: uData, v: vData,
                    yRowStride: yRowStride, uvRowStride: uvRowStride, uvPixelStride: uvPixelStride
                )
                result(["rgba": FlutterStandardTypedData(bytes: rgba)])
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // YUV420 → RGBA8888 변환. 카메라 시점 회전 처리는 호출자 책임.
    private static func convertYuvToRgba(
        width: Int, height: Int,
        y: Data, u: Data, v: Data,
        yRowStride: Int, uvRowStride: Int, uvPixelStride: Int
    ) -> Data {
        var rgba = Data(count: width * height * 4)
        rgba.withUnsafeMutableBytes { (rgbaPtr: UnsafeMutableRawBufferPointer) in
            y.withUnsafeBytes { (yPtr: UnsafeRawBufferPointer) in
                u.withUnsafeBytes { (uPtr: UnsafeRawBufferPointer) in
                    v.withUnsafeBytes { (vPtr: UnsafeRawBufferPointer) in
                        for j in 0..<height {
                            for i in 0..<width {
                                let yIdx = j * yRowStride + i
                                let uvIdx = (j / 2) * uvRowStride + (i / 2) * uvPixelStride
                                let Y = Int(yPtr[yIdx])
                                let U = Int(uPtr[uvIdx]) - 128
                                let V = Int(vPtr[uvIdx]) - 128
                                let r = max(0, min(255, Y + Int(Double(V) * 1.402)))
                                let g = max(0, min(255, Y + Int(Double(U) * -0.344 + Double(V) * -0.714)))
                                let b = max(0, min(255, Y + Int(Double(U) * 1.772)))
                                let out = (j * width + i) * 4
                                rgbaPtr[out]     = UInt8(r)
                                rgbaPtr[out + 1] = UInt8(g)
                                rgbaPtr[out + 2] = UInt8(b)
                                rgbaPtr[out + 3] = 255
                            }
                        }
                    }
                }
            }
        }
        return rgba
    }
}
