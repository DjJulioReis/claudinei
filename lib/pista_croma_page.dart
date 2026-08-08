import 'package:flutter/material.dart';

class PistaCromaPage extends StatefulWidget {
  final Function(String, String) enviarComando;
  const PistaCromaPage({super.key, required this.enviarComando});

  @override
  State<PistaCromaPage> createState() => _PistaCromaPageState();
}

class _PistaCromaPageState extends State<PistaCromaPage> {
  double _brilhoGeral = 100.0;
  double _velocidade = 100.0;
  Color _corAtiva = Colors.purple;

  void _enviarCor(Color cor) {
    widget.enviarComando("SET_COLOR", "${cor.red},${cor.green},${cor.blue}");
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.palette, color: Colors.purpleAccent),
                      SizedBox(width: 10),
                      Text(
                        "PISO CROMA RGB",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Controle de cores RGB completo com mixagem avançada e sincronização de efeitos do Piso Croma.",
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  const Divider(height: 32, color: Colors.white10),
                  const Text("Selecione uma Cor Rápida:", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildColorBtn(Colors.red),
                      _buildColorBtn(Colors.green),
                      _buildColorBtn(Colors.blue),
                      _buildColorBtn(Colors.purple),
                      _buildColorBtn(Colors.yellow),
                      _buildColorBtn(Colors.cyan),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("BRILHO GERAL", style: TextStyle(fontSize: 11)),
                      Text("${_brilhoGeral.toInt()}%", style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _brilhoGeral,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    activeColor: Colors.purpleAccent,
                    onChanged: (val) {
                      setState(() => _brilhoGeral = val);
                    },
                    onChangeEnd: (val) {
                      widget.enviarComando("SET_DIM", "${val.round()}");
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("VELOCIDADE DOS EFEITOS", style: TextStyle(fontSize: 11)),
                      Text("${_velocidade.toInt()}%", style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _velocidade,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    activeColor: Colors.purpleAccent,
                    onChanged: (val) {
                      setState(() => _velocidade = val);
                    },
                    onChangeEnd: (val) {
                      widget.enviarComando("SET_VEL", "${val.round()}");
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Simulador do piso Croma
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                const Text(
                  "SIMULADOR DE PISO CROMA (RGB)",
                  style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: _corAtiva.withOpacity((_brilhoGeral / 100.0).clamp(0.1, 0.6)),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: 16,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemBuilder: (context, index) {
                      final bool anim = index % 2 == 0;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        decoration: BoxDecoration(
                          color: anim ? _corAtiva.withOpacity((_brilhoGeral / 100.0).clamp(0.2, 1.0)) : _corAtiva.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white10),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorBtn(Color cor) {
    final bool sel = _corAtiva == cor;
    return GestureDetector(
      onTap: () {
        setState(() => _corAtiva = cor);
        _enviarCor(cor);
      },
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: cor,
          shape: BoxShape.circle,
          border: Border.all(
            color: sel ? Colors.white : Colors.transparent,
            width: 3,
          ),
          boxShadow: [
            if (sel)
              BoxShadow(color: cor.withOpacity(0.6), blurRadius: 10, spreadRadius: 2),
          ],
        ),
      ),
    );
  }
}