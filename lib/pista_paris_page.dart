import 'package:flutter/material.dart';

class PistaParisPage extends StatefulWidget {
  final int modoAtual;
  final double velocidad;
  final double brilhoGeral;
  final bool modoDMX;
  final int tamanhoGrade;
  final List<String> modosLista;
  final List<double> niveisReaisCanais;
  final int canalManualSelecionado;
  final List<double> brilhoCanaisManuais;
  final List<double> velocidadesCanaisManuais;
  final Function(String, String) enviarComando;
  final Function(int) setTamanhoGrade;
  final Function(int) setCanalManualSelecionado;
  final Function(bool) setModoDMX;
  final Function(int) setModoAtual;
  final Function(double) setVelocidad;
  final Function(double) setBrilhoGeral;

  const PistaParisPage({
    super.key,
    required this.modoAtual,
    required this.velocidad,
    required this.brilhoGeral,
    required this.modoDMX,
    required this.tamanhoGrade,
    required this.modosLista,
    required this.niveisReaisCanais,
    required this.canalManualSelecionado,
    required this.brilhoCanaisManuais,
    required this.velocidadesCanaisManuais,
    required this.enviarComando,
    required this.setTamanhoGrade,
    required this.setCanalManualSelecionado,
    required this.setModoDMX,
    required this.setModoAtual,
    required this.setVelocidad,
    required this.setBrilhoGeral,
  });

  @override
  State<PistaParisPage> createState() => _PistaParisPageState();
}

class _PistaParisPageState extends State<PistaParisPage> {
  Widget _buildPainelDMX() {
    return Column(
      children: [
        Card(
          color: const Color(0xFF1E1E1E),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const Text("ENDEREÇO DMX ATUAL", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildDmxControlBtn(Icons.remove, () {
                      // O endereço dmx pode ser controlado na main.dart
                      widget.enviarComando("DECREMENT_DMX", "1");
                    }),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      child: const Text("1", style: TextStyle(fontSize: 60, fontWeight: FontWeight.bold, color: Colors.cyan)),
                    ),
                    _buildDmxControlBtn(Icons.add, () {
                      widget.enviarComando("INCREMENT_DMX", "1");
                    }),
                  ],
                ),
                const SizedBox(height: 12),
                const Text("(Ajuste via Encoder ou Botões)", style: TextStyle(color: Colors.white24, fontSize: 11)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDmxControlBtn(IconData icon, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.cyan.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.cyan.withOpacity(0.3), width: 2),
        ),
        child: Icon(icon, color: Colors.cyan, size: 30),
      ),
    );
  }

  Widget _buildPainelManuais() {
    bool isManual = widget.modoAtual == 1;
    return Column(
      children: [
        Card(
          color: const Color(0xFF1E1E1E),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.modosLista.length - 1,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.2),
              itemBuilder: (context, index) {
                final int idxModo = index + 1;
                final bool sel = widget.modoAtual == idxModo;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: sel ? Colors.amber : const Color(0xFF2E2E2E),
                    foregroundColor: sel ? Colors.black : Colors.white,
                    padding: EdgeInsets.zero
                  ),
                  onPressed: () {
                    widget.setModoAtual(idxModo);
                    widget.enviarComando("SET_MODO", "$idxModo");
                  },
                  child: Text(widget.modosLista[idxModo], style: const TextStyle(fontSize: 10))
                );
              },
            ),
          ),
        ),
        if (isManual) ...[
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1E1E1E),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(4, (index) {
                    final int canal = index + 1;
                    final bool sel = widget.canalManualSelecionado == canal;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: index < 3 ? 8 : 0),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: sel ? Colors.amber : const Color(0xFF2E2E2E),
                            foregroundColor: sel ? Colors.black : Colors.white70,
                            padding: EdgeInsets.zero
                          ),
                          onPressed: () => widget.setCanalManualSelecionado(canal),
                          child: Text("CH$canal")
                        )
                      )
                    );
                  })),
                  const Divider(height: 32, color: Colors.white10),
                  _buildSliderRow(
                    "BRILHO CH${widget.canalManualSelecionado}",
                    widget.brilhoCanaisManuais[widget.canalManualSelecionado - 1],
                    (val) => setState(() => widget.brilhoCanaisManuais[widget.canalManualSelecionado - 1] = val),
                    "SET_CH${widget.canalManualSelecionado}"
                  ),
                  const SizedBox(height: 12),
                  _buildSliderRow(
                    "VELOCIDADE CH${widget.canalManualSelecionado}",
                    widget.velocidadesCanaisManuais[widget.canalManualSelecionado - 1],
                    (val) => setState(() => widget.velocidadesCanaisManuais[widget.canalManualSelecionado - 1] = val),
                    "SET_VCH${widget.canalManualSelecionado}"
                  ),
                ],
              ),
            ),
          ),
        ],
        if (!isManual) ...[
          const SizedBox(height: 8),
          _buildSliderCard(
            "VELOCIDADE EFEITO",
            widget.velocidad,
            (val) => widget.setVelocidad(val),
            "SET_VEL"
          ),
          const SizedBox(height: 8),
          _buildSliderCard(
            "BRILHO GERAL",
            widget.brilhoGeral,
            (val) => widget.setBrilhoGeral(val),
            "SET_DIM"
          ),
        ],
      ],
    );
  }

  Widget _buildSliderRow(String label, double val, Function(double) onCh, String cmd, {double min = 0, double max = 100}) {
    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 11)), Text("${val.toInt()}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))]),
        Slider(
          value: val,
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          activeColor: Colors.amber,
          onChanged: onCh,
          onChangeEnd: (v) => widget.enviarComando(cmd, "${v.round()}")
        ),
      ],
    );
  }

  Widget _buildSliderCard(String label, double val, Function(double) onCh, String cmd, {double min = 0, double max = 100}) {
    return Card(
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 11)), Text("${val.toInt()}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))]),
            Slider(
              value: val,
              min: min,
              max: max,
              divisions: (max - min).toInt(),
              activeColor: Colors.amber,
              onChanged: onCh,
              onChangeEnd: (v) => widget.enviarComando(cmd, "${v.round()}")
            ),
          ],
        )
      )
    );
  }

  Widget _buildSimuladorPistaLed() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("ANÁLISE GERAL (PISO)", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              DropdownButton<int>(
                value: widget.tamanhoGrade,
                dropdownColor: const Color(0xFF1E1E1E),
                items: [3, 4, 5, 6].map((int i) => DropdownMenuItem(value: i, child: Text("${i}x$i  "))).toList(),
                onChanged: (v) => widget.setTamanhoGrade(v!)
              )
            ]
          ),
          const SizedBox(height: 12),
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(8)),
            child: CustomPaint(painter: LedGridPainter(gridSize: widget.tamanhoGrade, niveisCanais: widget.niveisReaisCanais))
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ElevatedButton(onPressed: () => widget.enviarComando("EFEITO_PISTA", "START"), child: const Text("TESTAR PISTA"))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(onPressed: () => widget.enviarComando("EFEITO_PISTA", "CLEAR"), child: const Text("APAGAR")))
            ]
          ),
        ],
      ),
    );
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
            child: ListTile(
              title: Text(widget.modoDMX ? "MODO DMX ATIVO" : "MODO MANUAL / DMX", style: TextStyle(fontWeight: FontWeight.bold, color: widget.modoDMX ? Colors.cyan : Colors.amber)),
              trailing: Switch(
                value: widget.modoDMX,
                activeColor: Colors.cyan,
                onChanged: (v) {
                  widget.setModoDMX(v);
                  widget.setModoAtual(v ? 0 : 1);
                  widget.enviarComando("CHAVE_MODO", v ? "DMX" : "RF");
                }
              ),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: widget.modoDMX ? _buildPainelDMX() : _buildPainelManuais()
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            icon: const Icon(Icons.save),
            label: const Text("GRAVAR NA MEMÓRIA"),
            onPressed: () => widget.enviarComando("GRAVAR", "1")
          ),
          const SizedBox(height: 24),
          _buildSimuladorPistaLed(),
        ],
      ),
    );
  }
}

class LedGridPainter extends CustomPainter {
  final int gridSize;
  final List<double> niveisCanais;
  LedGridPainter({required this.gridSize, required this.niveisCanais});
  @override
  void paint(Canvas canvas, Size size) {
    double sw = size.width / gridSize, sh = size.height / gridSize;
    for (int i = 0; i < gridSize * gridSize; i++) {
      int r = i ~/ gridSize, c = i % gridSize;

      final Rect rect = Rect.fromLTWH(c * sw, r * sh, sw - 2, sh - 2);

      bool ehPar = (r + c) % 2 == 0;
      int ch1 = ehPar ? 0 : 2;
      int ch2 = ehPar ? 1 : 3;

      double n1 = niveisCanais[ch1] / 100.0;
      double n2 = niveisCanais[ch2] / 100.0;

      if (n1 == 0 && n2 == 0) {
        canvas.drawRect(rect, Paint()..color = Colors.grey.shade900);
      } else {
        double total = (n1 + n2).clamp(0.001, 2.0);
        int red = (((224 * n1) + (255 * n2)) / total).round();
        int green = (((232 * n1) + (227 * n2)) / total).round();
        int blue = (((255 * n1) + (163 * n2)) / total).round();

        canvas.drawRect(
          rect,
          Paint()..color = Color.fromARGB(255, red, green, blue).withOpacity(((n1 + n2) / 1.5).clamp(0.3, 1.0)),
        );
      }
    }
  }
  @override
  bool shouldRepaint(covariant LedGridPainter old) => old.niveisCanais != niveisCanais || old.gridSize != gridSize;
}