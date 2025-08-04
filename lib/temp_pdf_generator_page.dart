// lib/temp_pdf_generator_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class TempPdfGeneratorPage extends StatefulWidget {
  const TempPdfGeneratorPage({super.key});

  @override
  State<TempPdfGeneratorPage> createState() => _TempPdfGeneratorPageState();
}

class _TempPdfGeneratorPageState extends State<TempPdfGeneratorPage> {
  bool _isGenerating = false;

  pw.Widget _buildTable(PdfColor themeColor, List<String> headers, List<List<String>> data, {Map<int, pw.TableColumnWidth>? columnWidths}) {
    return pw.Table.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: PdfColors.grey),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: themeColor),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: { for (var i = 1; i < headers.length; i++) i: pw.Alignment.center },
      columnWidths: columnWidths,
    );
  }

  Future<void> _generatePricingPdf() async {
    setState(() => _isGenerating = true);

    try {
      final pdf = pw.Document();
      final themeColor = PdfColor.fromHex('4DB6AC');

      // --- Page 1: Title Page (Landscape) ---
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(
            color: themeColor,
            alignment: pw.Alignment.center,
            child: pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text('ClockEr, SchedulEr, ScheduleLink',
                      style: pw.TextStyle(color: PdfColors.white, fontSize: 36, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 12),
                  pw.Text('Developing solutions to streamline productivity',
                      style: const pw.TextStyle(color: PdfColors.white, fontSize: 18)),
                  pw.SizedBox(height: 24),
                  pw.Text('Pricing Overview - August 2025',
                      style: const pw.TextStyle(color: PdfColors.white, fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
      ));

      // --- Main Content Pages (Landscape with Page Numbers) ---
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          orientation: pw.PageOrientation.landscape,
          build: (context) => [
            pw.Header(text: 'ScheduleLink - Pricing Overview'),
            pw.Wrap(
                children: [
                  pw.Header(level: 2, text: 'Core Software Pricing Tiers', textStyle: pw.TextStyle(color: themeColor, fontWeight: pw.FontWeight.bold)),
                  _buildTable(themeColor,
                    ['Feature', 'Starter / Offline', 'Growth', 'Scale / Full Cloud', 'Enterprise'],
                    const [
                      ['Ideal For', '< 15 staff', '15 / 75 staff', '75 / 300 staff', 'Custom needs'],
                      ['Price', '£69 / device (one-time)', 'From £99 / month', 'From £199 / month', 'Custom'],
                      ['Setup Fee', '-', '£599', '£999', 'Custom'],
                      ['SchedulEr & ClockEr Apps', 'Yes', 'Yes', 'Yes', 'Yes'],
                      ['ScheduleLink Web App', '-', 'Optional Add-on', 'Yes', 'Yes'],
                    ],
                  ),
                ]
            ),
            pw.SizedBox(height: 24),
            pw.Wrap(
                children: [
                  pw.Header(level: 2, text: "What's Included in Your Setup Fee?", textStyle: pw.TextStyle(color: themeColor, fontWeight: pw.FontWeight.bold)),
                  pw.Paragraph(text: "Our one-time setup fees for the Growth, Scale, and Enterprise tiers are designed to ensure a seamless transition for your team. This fee covers personalized onboarding, including a full user manual, a \"show and tell\" training session for your managers, and initial support hours for any questions or minor debugging. This is a partnership to ensure you start with confidence. Please note this fee does not cover major feature redevelopment."),
                ]
            ),
            pw.NewPage(),
            pw.Wrap(
                children: [
                  pw.Header(level: 2, text: 'Alternative Plan: Pay-As-You-Go', textStyle: pw.TextStyle(color: themeColor, fontWeight: pw.FontWeight.bold)),
                  _buildTable(themeColor,
                    ['Plan Name', 'Price', 'Included Features'],
                    const [
                      ['Flex Plan', '£129 set up + £10 / month base + £4 / active user', 'All Growth tier features with ScheduleLink Cloud Platform (seasonal)'],
                    ],
                  ),
                ]
            ),
            pw.SizedBox(height: 24),
            pw.Wrap(
                children: [
                  pw.Header(level: 2, text: 'Optional Add-ons & Custom Solutions', textStyle: pw.TextStyle(color: themeColor, fontWeight: pw.FontWeight.bold)),
                  _buildTable(themeColor,
                      ['Category', 'Service / Module', 'Price', 'Description'],
                      const [
                        ['Platform Upgrade', 'ScheduleLink Cloud Platform (For Growth Tier)', '+ £29 / month', 'Enables the full web app, real-time sync, cloud reports, and time-off features.'],
                        ['Mobile Solutions', 'Native Android Apps', 'Custom Quote', 'Optimized native mobile versions of our apps for the fastest experience.'],
                        ['Custom Development', 'Bespoke Training App', 'From £3,999 + £179 / month', 'Track in-house H&S certifications, deliver internal training modules, etc.'],
                        ['Custom Development', 'Custom Stock App', 'From £2,999 + £149 / month', 'Inventory and stock-keeping tools tailored to your specific workflow.'],
                        ['Services', 'Private Servers', 'Custom Quote', 'Dedicated server hosting for maximum security and data control (Scale+).'],
                      ],
                      columnWidths: { 3: const pw.FlexColumnWidth(2) }
                  ),
                ]
            ),
          ],
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(color: PdfColors.grey)),
          ),
        ),
      );

      // --- Final Page (Landscape) ---
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) {
          return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(text: 'ScheduleLink - Our Partnership Approach'),
                pw.Padding(
                  // CORRECTED: Use pw.EdgeInsets
                  padding: const pw.EdgeInsets.all(30),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Header(level: 2, text: 'Our Partnership Approach', textStyle: pw.TextStyle(color: themeColor, fontWeight: pw.FontWeight.bold)),
                      pw.Paragraph(text: "At our core, we are problem-solvers. We believe that software should adapt to your business, not the other way around. The plans above provide a clear guideline, but we are a flexible and approachable team based here in Northern Ireland. If you have a specific need or a unique workflow that isn't covered, we are always open to a conversation."),
                      pw.SizedBox(height: 12),
                      pw.Paragraph(text: "We provide our software as a service; you do not receive install files or source code. This ensures you always have the latest, most secure, and fully supported version of the platform. We are passionate about creating streamlined productivity tools for the modern workplace. Tell us your challenge, and we will work with you to make a solution happen."),
                      pw.SizedBox(height: 12),
                      pw.Paragraph(
                          text: "Disclaimer: All prices are for guidance and subject to change. Final pricing will be confirmed via a formal quote. Growth, Scale and Enterprise tiers are subject to a minimum term agreement.",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontStyle: pw.FontStyle.italic)
                      ),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Align(
                    alignment: pw.Alignment.bottomRight,
                    child: pw.Padding(
                      // CORRECTED: Use pw.EdgeInsets
                      padding: const pw.EdgeInsets.all(30),
                      child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(color: PdfColors.grey)),
                    )
                ),
              ]
          );
        },
      ));

      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/ScheduleLink_Pricing_Overview.pdf';
      final file = File(path);
      await file.writeAsBytes(await pdf.save());

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF saved to $path'), backgroundColor: Colors.green));
        await OpenFile.open(path);
      }

    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating PDF: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if(mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generate Pricing PDF')),
      body: Center(
        child: Padding(
          // This padding uses the standard material EdgeInsets, which is correct here.
          padding: const EdgeInsets.all(24.0),
          child: _isGenerating
              ? const CircularProgressIndicator()
              : ElevatedButton.icon(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Generate Final Pricing PDF'),
            onPressed: _generatePricingPdf,
          ),
        ),
      ),
    );
  }
}