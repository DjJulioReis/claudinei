import 'package:flutter/material.dart';

class PistaLedPage extends StatefulWidget {
  const PistaLedPage({super.key});

  @override
  State<PistaLedPage> createState() => _PistaLedPageState();
}

class _PistaLedPageState extends State<PistaLedPage> {
  // Simulação de 60 pixels de LED (representando a Orion ou fita)
  final int totalLeds = 60;
  late List<Color> ledColors;
  bool executandoEfeito = false;

  @override
  void initState() {
    super.initState();
    // Inicializa todos os LEDs desligados (cor cinza escuro/preto)
    ledColors = List.generate(totalLeds, (index) => Colors.grey.shade900);
  }

  // Função para simular um efeito de "Onda de Luz" (Knight Rider / Sequencial)
  void _rodarEfeitoSequencial() async {
    if (executandoEfeito) return;
    setState(() => executandoEfeito = true);

    for (int i = 0; i < totalLeds; i++) {
      if (!mounted) return;
      setState(() {
        // Apaga o anterior e acende o atual com brilho (RGBW)
        if (i > 0) ledColors[i - 1] = Colors.grey.shade900;
        ledColors[i] = Colors.cyanAccent; // Cor do LED ativo
      });
      await Future.delayed(const Duration(milliseconds: 50)); // Velocidade do efeito
    }

    // Apaga o último LED no final do efeito
    setState(() {
      ledColors[totalLeds - 1] = Colors.grey.shade900;
      executandoEfeito = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Fundo preto destaca o LED
      appBar: AppBar(
        title: const Text('Simulador de Pista LED'),
        backgroundColor: Colors.grey.shade900,
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Visualização Digital dos Pixels (Orion)',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),

          // O Painel onde a mágica do CustomPainter acontece
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                width: MediaQuery.of(context).size.width * 0.9,
                height: 250,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A), //  Resolvido! Um cinza quase preto bem escuro
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                ),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: LedGridPainter(ledColors: ledColors, columns: 10),
                ),
              ),
            ),
          ),

          // Controles Interativos da Pista
          Padding(
            padding: const EdgeInsets.only(bottom: 40.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _rodarEfeitoSequencial,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Efeito Sequencial'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      // Desliga tudo ou reseta
                      ledColors = List.generate(totalLeds, (index) => Colors.grey.shade900);
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Resetar Pista'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// O Pintor Customizado que desenha os LEDs com efeito de brilho (Glow)
class LedGridPainter extends CustomPainter {
  final List<Color> ledColors;
  final int columns;

  LedGridPainter({required this.ledColors, required this.columns});

  @override
  void paint(Canvas canvas, Size size) {
    final int totalLeds = ledColors.length;
    final int rows = (totalLeds / columns).ceil();

    final double cellWidth = size.width / columns;
    final double cellHeight = size.height / rows;
    final double radius = (cellWidth < cellHeight ? cellWidth : cellHeight) * 0.35;

    for (int i = 0; i < totalLeds; i++) {
      final int row = i ~/ columns;
      final int col = i % columns;

      final double centerX = col * cellWidth + cellWidth / 2;
      final double centerY = row * cellHeight + cellHeight / 2;
      final Offset center = Offset(centerX, centerY);

      // 1. Desenha o efeito Glow (Brilho espalhado se o LED estiver aceso)
      if (ledColors[i] != Colors.grey.shade900) {
        final Paint glowPaint = Paint()
          ..color = ledColors[i].withOpacity(0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8); // Cria o efeito esfumaçado de luz
        canvas.drawCircle(center, radius * 1.5, glowPaint);
      }

      // 2. Desenha o LED físico principal
      final Paint ledPaint = Paint()
        ..color = ledColors[i]
        ..style = PaintingStyle.fill;

      canvas.drawCircle(center, radius, ledPaint);
    }
  }

  @override
  bool shouldRepaint(covariant LedGridPainter oldDelegate) {
    // Repinta a tela sempre que a lista de cores mudar
    return oldDelegate.ledColors != ledColors;
  }
}