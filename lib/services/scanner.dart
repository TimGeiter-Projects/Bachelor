import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:translator/translator.dart';

class BarcodeScanner {
  static final GoogleTranslator translator = GoogleTranslator(); // Übersetzer

  static Future<String?> scanBarcode(BuildContext context) async {
    String? scannedCode;
    final scanController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          bool hasScanned = false;

          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                AppBar(
                  title: const Text('Barcode Scanner'),
                  backgroundColor: Theme.of(context).colorScheme.inversePrimary,
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      scanController.stop();
                      Navigator.pop(context);
                    },
                  ),
                  actions: [
                    IconButton(
                      icon: ValueListenableBuilder(
                        valueListenable: scanController.torchState,
                        builder: (context, state, child) {
                          return Icon(
                            state == TorchState.on ? Icons.flash_on : Icons.flash_off,
                          );
                        },
                      ),
                      onPressed: () => scanController.toggleTorch(),
                    ),
                    IconButton(
                      icon: ValueListenableBuilder(
                        valueListenable: scanController.cameraFacingState,
                        builder: (context, state, child) {
                          return Icon(
                            state == CameraFacing.front ? Icons.camera_front : Icons.camera_rear,
                          );
                        },
                      ),
                      onPressed: () => scanController.switchCamera(),
                    ),
                  ],
                ),
                Expanded(
                  child: MobileScanner(
                    controller: scanController,
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty &&
                          barcodes[0].rawValue != null &&
                          !hasScanned) {
                        hasScanned = true;
                        scannedCode = barcodes[0].rawValue;
                        scanController.stop();
                        Navigator.pop(context, scannedCode);
                      }
                    },
                    overlay: const Center(
                      child: SizedBox(
                        width: 200,
                        height: 200,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.red, width: 3),
                              right: BorderSide(color: Colors.red, width: 3),
                              bottom: BorderSide(color: Colors.red, width: 3),
                              left: BorderSide(color: Colors.red, width: 3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Positioniere den Barcode im Rahmen',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      scanController.stop();
    }

    return scannedCode;
  }


  static Future<String?> getProductNameFromBarcode(String barcode) async {
    try {
      final uri = Uri.parse(
          'https://world.openfoodfacts.org/api/v2/product/$barcode?fields=product_name,brands');

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        if (data['product'] != null && data['product'].isNotEmpty) {
          final product = data['product'];

          // Nur den Produktnamen extrahieren
          String name = product['product_name'] ?? 'Unknown Product';

          try {
            // Übersetzung versuchen
            var translatedName = await translator.translate(name, from: 'de', to: 'en');
            return translatedName.text;
          } catch (e) {
            print("Übersetzungsfehler: $e");
            // Bei Fehlern den Originalnamen zurückgeben
            return name;
          }
        } else {
          return null;
        }
      } else {
        return null;
      }
    } catch (e) {
      print("Error querying $barcode: $e");
      return null;
    }
  }

  static Future<void> scanAndFillProductName(
      BuildContext context, TextEditingController controller) async {
    final String? barcode = await scanBarcode(context);
    if (barcode != null) {
      final String? productName = await getProductNameFromBarcode(barcode);
      controller.text = productName ?? 'Unknown Product';
    }
  }
}