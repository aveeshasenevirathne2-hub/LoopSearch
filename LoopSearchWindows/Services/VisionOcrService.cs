using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;

namespace LoopSearch.Services;

public static class VisionOcrService
{
    public static async Task<VisionAnalysisResult> AnalyzeBitmapAsync(Bitmap bitmap)
    {
        var blocks = new List<NormalizedTextBlock>();
        string ocrText = "";
        string? dominantHex = null;
        bool isLowInfo = false;

        try
        {
            // Analyze pixels for dominant color & low-info check
            var rect = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
            var bmpData = bitmap.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            byte[] bgraBytes;
            try
            {
                int byteCount = Math.Abs(bmpData.Stride) * bitmap.Height;
                bgraBytes = new byte[byteCount];
                Marshal.Copy(bmpData.Scan0, bgraBytes, 0, byteCount);
            }
            finally
            {
                bitmap.UnlockBits(bmpData);
            }

            (dominantHex, isLowInfo) = ColorAnalyzer.AnalyzeBgraPixels(bgraBytes, bitmap.Width, bitmap.Height);

            // Run Windows Native WinRT OcrEngine
            var engine = OcrEngine.TryCreateFromUserProfileLanguages();
            if (engine != null && bitmap.Width > 8 && bitmap.Height > 8)
            {
                using var softBmp = SoftwareBitmap.CreateCopyFromBuffer(
                    bgraBytes.AsBuffer(),
                    BitmapPixelFormat.Bgra8,
                    bitmap.Width,
                    bitmap.Height,
                    BitmapAlphaMode.Premultiplied);

                var ocrResult = await engine.RecognizeAsync(softBmp);
                if (ocrResult != null && !string.IsNullOrWhiteSpace(ocrResult.Text))
                {
                    ocrText = ocrResult.Text.Trim();
                    double w = bitmap.Width;
                    double h = bitmap.Height;

                    foreach (var line in ocrResult.Lines)
                    {
                        foreach (var word in line.Words)
                        {
                            var r = word.BoundingRect;
                            blocks.Add(new NormalizedTextBlock(
                                word.Text,
                                r.X / w,
                                r.Y / h,
                                r.Width / w,
                                r.Height / h));
                        }
                    }
                }
            }
        }
        catch
        {
            // Graceful fallback if WinRT OCR language pack is unavailable
        }

        var cleanPreview = TextInsightHelper.MakeCleanPreview(ocrText);
        var detectedUrl = TextInsightHelper.ExtractFirstUrl(ocrText);
        var mathAnswer = MathEvaluator.TryEvaluate(ocrText);

        return new VisionAnalysisResult(
            OcrText: ocrText,
            CleanPreview: cleanPreview,
            DetectedUrl: detectedUrl,
            MathAnswer: mathAnswer,
            DominantHex: dominantHex,
            TextBlocks: blocks,
            IsLowInformation: isLowInfo && string.IsNullOrWhiteSpace(ocrText));
    }

    public static byte[] EncodeJpeg(Bitmap bitmap, long quality = 88L)
    {
        using var ms = new MemoryStream();
        var encoder = ImageCodecInfo.GetImageEncoders().FirstOrDefault(e => e.FormatID == ImageFormat.Jpeg.Guid);
        if (encoder != null)
        {
            using var encParams = new EncoderParameters(1);
            encParams.Param[0] = new EncoderParameter(Encoder.Quality, quality);
            bitmap.Save(ms, encoder, encParams);
        }
        else
        {
            bitmap.Save(ms, ImageFormat.Jpeg);
        }
        return ms.ToArray();
    }

    public static byte[] EncodePng(Bitmap bitmap)
    {
        using var ms = new MemoryStream();
        bitmap.Save(ms, ImageFormat.Png);
        return ms.ToArray();
    }
}
