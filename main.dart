import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

void main() {
  runApp(const WeddingAlbumApp());
}

class WeddingAlbumApp extends StatelessWidget {
  const WeddingAlbumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto Wedding Album Maker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD4AF37)),
        useMaterial3: true,
      ),
      home: const AlbumHomeScreen(),
    );
  }
}

class AlbumHomeScreen extends StatefulWidget {
  const AlbumHomeScreen({super.key});

  @override
  State<AlbumHomeScreen> createState() => _AlbumHomeScreenState();
}

class _AlbumHomeScreenState extends State<AlbumHomeScreen> {
  List<File> _selectedImages = [];
  String _selectedSize = "12x36";
  bool _isProcessing = false;
  String _statusMessage = "Photos select karein aur album generate karein";
  double _progressValue = 0.0;
  String? _generatedPdfPath;

  // Album dimensions in Inches
  final Map<String, Size> _albumSizes = {
    "12x36": const Size(36.0, 12.0),
    "24x36": const Size(36.0, 24.0),
    "12x30": const Size(30.0, 12.0),
    "12x18": const Size(18.0, 12.0),
  };

  Future<void> _pickImages() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );

      if (result != null && result.paths.isNotEmpty) {
        setState(() {
          _selectedImages = result.paths
              .whereType<String>()
              .map((path) => File(path))
              .toList();
          _generatedPdfPath = null;
          _statusMessage = "${_selectedImages.length} photos select hui hain";
          _progressValue = 0.0;
        });
      }
    } catch (e) {
      _showSnackBar("Error selecting photos: $e");
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Auto-enhance photo: Exposure leveling, vibrant color boost, gentle skin softening
  img.Image _autoEnhanceAndRetouch(img.Image original) {
    // 1. Auto Levels / Contrast Normalization
    img.Image enhanced = img.normalize(original, min: 0, max: 255);

    // 2. Adjust Brightness & Saturation for Indian Wedding tones (warm, vibrant colors)
    enhanced = img.adjustColor(
      enhanced,
      brightness: 1.05,
      contrast: 1.08,
      saturation: 1.12,
    );

    // 3. Gentle Skin Smoothing (Gaussian blur blend to soften blemishes without losing sharpness)
    img.Image blurred = img.gaussianBlur(img.Image.from(enhanced), radius: 2);
    // Blend blurred layer at 35% opacity with sharp original
    for (int y = 0; y < enhanced.height; y++) {
      for (int x = 0; x < enhanced.width; x++) {
        final origPixel = enhanced.getPixel(x, y);
        final blurPixel = blurred.getPixel(x, y);

        // Soft skin blend
        final r = (origPixel.r * 0.65 + blurPixel.r * 0.35).round();
        final g = (origPixel.g * 0.65 + blurPixel.g * 0.35).round();
        final b = (origPixel.b * 0.65 + blurPixel.b * 0.35).round();

        enhanced.setPixelRgb(x, y, r, g, b);
      }
    }

    return enhanced;
  }

  Future<void> _generateAlbumPdf() async {
    if (_selectedImages.isEmpty) {
      _showSnackBar("Pehle photos select karein!");
      return;
    }

    setState(() {
      _isProcessing = true;
      _progressValue = 0.0;
      _statusMessage = "Processing photos...";
    });

    try {
      final pdf = pw.Document();
      final sizeConfig = _albumSizes[_selectedSize]!;
      // PDF points: 1 inch = 72 points
      final pdfPageWidth = sizeConfig.width * PdfPageFormat.inch;
      final pdfPageHeight = sizeConfig.height * PdfPageFormat.inch;
      final pageFormat = PdfPageFormat(pdfPageWidth, pdfPageHeight);

      // Sheet layout logic:
      // For 12x36: 4 photos per sheet (horizontal row)
      // For 24x36: 6 photos per sheet (2 rows x 3 columns)
      final int photosPerSheet = (_selectedSize == "24x36") ? 6 : 4;
      final int totalPhotos = _selectedImages.length;
      final int totalSheets = (totalPhotos / photosPerSheet).ceil();

      for (int sheetIdx = 0; sheetIdx < totalSheets; sheetIdx++) {
        int start = sheetIdx * photosPerSheet;
        int end = (start + photosPerSheet > totalPhotos) ? totalPhotos : start + photosPerSheet;
        List<File> currentBatch = _selectedImages.sublist(start, end);

        List<Uint8List> processedBytesList = [];

        for (int p = 0; p < currentBatch.length; p++) {
          int currentGlobalIndex = start + p + 1;
          setState(() {
            _statusMessage = "Retouching Photo $currentGlobalIndex of $totalPhotos...";
            _progressValue = currentGlobalIndex / totalPhotos;
          });

          // Read image
          Uint8List bytes = await currentBatch[p].readAsBytes();
          img.Image? decoded = img.decodeImage(bytes);

          if (decoded != null) {
            // Auto enhance & skin retouch
            img.Image retouched = _autoEnhanceAndRetouch(decoded);
            processedBytesList.add(Uint8List.fromList(img.encodeJpg(retouched, quality: 92)));
          }
        }

        // Add sheet to PDF
        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.all(18),
            build: (pw.Context ctx) {
              if (_selectedSize == "24x36") {
                // 2 Rows x 3 Cols
                return pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: [
                    pw.Expanded(
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                        children: processedBytesList.take(3).map((b) {
                          return pw.Expanded(
                            child: pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Image(pw.MemoryImage(b), fit: pw.BoxFit.cover),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                        children: processedBytesList.skip(3).map((b) {
                          return pw.Expanded(
                            child: pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Image(pw.MemoryImage(b), fit: pw.BoxFit.cover),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              } else {
                // Single Row (12x36 / 12x30 / 12x18)
                return pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: processedBytesList.map((b) {
                    return pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Image(pw.MemoryImage(b), fit: pw.BoxFit.cover),
                      ),
                    );
                  }).toList(),
                );
              }
            },
          ),
        );
      }

      setState(() {
        _statusMessage = "Saving Print PDF...";
      });

      // Save PDF to Documents/Downloads folder
      final outputDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File("${outputDir.path}/WeddingAlbum_${_selectedSize}_$timestamp.pdf");
      await file.writeAsBytes(await pdf.save());

      setState(() {
        _isProcessing = false;
        _progressValue = 1.0;
        _generatedPdfPath = file.path;
        _statusMessage = "Album ready! Sidhe print ke liye ready hai.";
      });

      _showSnackBar("PDF successfully create ho gayi!");
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "Error: $e";
      });
      _showSnackBar("Album banane me error aaya: $e");
    }
  }

  void _openGeneratedPdf() {
    if (_generatedPdfPath != null) {
      OpenFilex.open(_generatedPdfPath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF9F5),
      appBar: AppBar(
        title: const Text(
          "Auto Wedding Album Maker",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFD4AF37),
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner Card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: const [
                    Icon(Icons.auto_fix_high, size: 48, color: Color(0xFFD4AF37)),
                    SizedBox(height: 10),
                    Text(
                      "Zero-Touch Album Engine",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 6),
                    Text(
                      "• Auto Color & Contrast Balance\n• Auto Skin Finer & Smoothing\n• Auto Aspect Fit (No Stretch)\n• Print-Ready Vector PDF Export",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black87, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Select Album Sheet Size
            const Text(
              "Sheet Size Chunein:",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.pad(BorderSide(color: Colors.grey.shade300)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedSize,
                  isExpanded: true,
                  items: _albumSizes.keys.map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Text(
                        "$s Inch (Wedding Standard)",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                  onChanged: _isProcessing
                      ? null
                      : (val) {
                          if (val != null) setState(() => _selectedSize = val);
                        },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Pick Photos Button
            ElevatedButton.icon(
              icon: const Icon(Icons.add_photo_alternate, size: 24),
              label: Text(
                _selectedImages.isEmpty
                    ? "Select Wedding Photos"
                    : "Change Selected Photos (${_selectedImages.length})",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isProcessing ? null : _pickImages,
            ),
            const SizedBox(height: 15),

            // Photos Preview Grid if selected
            if (_selectedImages.isNotEmpty) ...[
              Text(
                "Selected Photos (${_selectedImages.length})",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  itemBuilder: (ctx, idx) {
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: FileImage(_selectedImages[idx]),
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Progress & Status Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.pad(BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  if (_isProcessing) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _progressValue > 0 ? _progressValue : null,
                      backgroundColor: Colors.grey.shade200,
                      color: const Color(0xFFD4AF37),
                      minHeight: 8,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Generate Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: (_selectedImages.isEmpty || _isProcessing)
                  ? null
                  : _generateAlbumPdf,
              child: _isProcessing
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text(
                      "Make Print-Ready PDF",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),

            if (_generatedPdfPath != null) ...[
              const SizedBox(height: 15),
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                label: const Text(
                  "Open & Share Print PDF",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _openGeneratedPdf,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
