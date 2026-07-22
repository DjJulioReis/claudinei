import 'dart:async';
import 'package:flutter/material.dart';

class MesaDmxPage extends StatefulWidget {
  final List<double> fadersDMX8;
  final List<Map<String, dynamic>> cenasSalvas;
  final bool executandoShow;
  final int indiceCenaShow;
  final double tempoTransicaoShow;
  final List<String> modosLista;
  final int modoAtual;
  final double velocidad;
  final double brilhoGeral;
  final List<double> brilhoCanaisManuais;
  final List<double> velocidadesCanaisManuais;
  final Function(String, String) enviarComando;
  final Function(String) mostrarFeedback;
  final Function(Map<String, dynamic>) dispararCena;
  final VoidCallback iniciarShowDeCenas;
  final VoidCallback pararShowDeCenas;
  final Function(double) setTempoTransicaoShow;
  final Function(List<Map<String, dynamic>>) setCenasSalvas;

  const MesaDmxPage({
    super.key,
    required this.fadersDMX8,
    required this.cenasSalvas,
    required this.executandoShow,
    required this.indiceCenaShow,
    required this.tempoTransicaoShow,
    required this.modosLista,
    required this.modoAtual,
    required this.velocidad,
    required this.brilhoGeral,
    required this.brilhoCanaisManuais,
    required this.velocidadesCanaisManuais,
    required this.enviarComando,
    required this.mostrarFeedback,
    required this.dispararCena,
    required this.iniciarShowDeCenas,
    required this.pararShowDeCenas,
    required this.setTempoTransicaoShow,
    required this.setCenasSalvas,
  });

  @override
  State<MesaDmxPage> createState() => _MesaDmxPageState();
}

class _MesaDmxPageState extends State<MesaDmxPage> {
  Widget _buildFaderCanal(int index) {
    final int canal = index + 1;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Text(
              "CH $canal",
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: widget.fadersDMX8[index],
                    min: 0,
                    max: 255,
                    divisions: 255,
                    activeColor: Colors.cyan,
                    inactiveColor: Colors.white10,
                    onChanged: (val) {
                      setState(() {
                        widget.fadersDMX8[index] = val;
                      });
                    },
                    onChangeEnd: (val) {
                      widget.enviarComando("SET_CH$canal", "${val.round()}");
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "${widget.fadersDMX8[index].round()}",
              style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tune, color: Colors.cyan, size: 20),
                          SizedBox(width: 8),
                          Text(
                            "MESA DMX MANUAL - 8 CANAIS",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                        onPressed: () {
                          setState(() {
                            for (int i = 0; i < 8; i++) {
                              widget.fadersDMX8[i] = 0.0;
                            }
                          });
                          for (int i = 1; i <= 8; i++) {
                            widget.enviarComando("SET_CH$i", "0");
                          }
                          widget.mostrarFeedback("Mesa DMX resetada!");
                        },
                        icon: const Icon(Icons.clear_all, color: Colors.redAccent, size: 16),
                        label: const Text("Zerar", style: TextStyle(color: Colors.redAccent, fontSize: 10)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 380,
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              _buildFaderCanal(0),
                              _buildFaderCanal(1),
                              _buildFaderCanal(2),
                              _buildFaderCanal(3),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Row(
                            children: [
                              _buildFaderCanal(4),
                              _buildFaderCanal(5),
                              _buildFaderCanal(6),
                              _buildFaderCanal(7),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildPainelCenasIntegrado(),
        ],
      ),
    );
  }

  Widget _buildPainelCenasIntegrado() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.video_collection, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "GRAVADOR DE CENAS E SHOWS",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  "Grave os níveis atuais dos faders DMX (CH1 a CH8) como uma cena personalizada.",
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text("SALVAR NÍVEIS ATUAIS COMO CENA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    final TextEditingController controller = TextEditingController(text: "Cena ${widget.cenasSalvas.length + 1}");
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          backgroundColor: const Color(0xFF1E1E1E),
                          title: const Text("Salvar Nova Cena DMX", style: TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold)),
                          content: TextField(
                            controller: controller,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: "Nome da Cena",
                              labelStyle: TextStyle(color: Colors.grey),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                              onPressed: () {
                                setState(() {
                                  widget.cenasSalvas.add({
                                    "nome": controller.text,
                                    "modo": widget.modoAtual,
                                    "vel": widget.velocidad,
                                    "dim": widget.brilhoGeral,
                                    "faders": List<double>.from(widget.fadersDMX8),
                                    "brilhos": List<double>.from(widget.brilhoCanaisManuais),
                                    "velocidades": List<double>.from(widget.velocidadesCanaisManuais),
                                  });
                                  widget.setCenasSalvas(widget.cenasSalvas);
                                });
                                Navigator.pop(context);
                                widget.mostrarFeedback("Cena '${controller.text}' gravada com sucesso!");
                              },
                              child: const Text("GRAVAR CENA", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (widget.cenasSalvas.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "PLAYLIST DO SHOW (LOOP SEQUENCIAL)",
                    style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Intervalo: ${widget.tempoTransicaoShow.toStringAsFixed(1)}s", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: widget.tempoTransicaoShow,
                          min: 1.0,
                          max: 15.0,
                          divisions: 14,
                          activeColor: Colors.amber,
                          onChanged: widget.executandoShow ? null : (val) {
                            widget.setTempoTransicaoShow(val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10)),
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text("INICIAR SHOW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: widget.executandoShow ? null : widget.iniciarShowDeCenas,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10)),
                          icon: const Icon(Icons.stop, size: 18),
                          label: const Text("PARAR SHOW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: !widget.executandoShow ? null : widget.pararShowDeCenas,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.cenasSalvas.length,
            itemBuilder: (context, index) {
              final cena = widget.cenasSalvas[index];
              final bool estaAtivaNoShow = widget.executandoShow && widget.indiceCenaShow == index;
              return Card(
                color: estaAtivaNoShow ? Colors.amber.withOpacity(0.15) : const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: estaAtivaNoShow ? Colors.amber : Colors.white10),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: estaAtivaNoShow ? Colors.amber : const Color(0xFF2E2E2E),
                    foregroundColor: estaAtivaNoShow ? Colors.black : Colors.white70,
                    child: Text("${index + 1}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(cena['nome'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                  subtitle: Text(
                    "Cena DMX Gravada",
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.touch_app, color: Colors.amber, size: 20),
                        tooltip: "Disparar Cena",
                        onPressed: () => widget.dispararCena(cena),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        tooltip: "Excluir Cena",
                        onPressed: () {
                          setState(() {
                            widget.cenasSalvas.removeAt(index);
                            widget.setCenasSalvas(widget.cenasSalvas);
                            if (widget.cenasSalvas.isEmpty && widget.executandoShow) {
                              widget.pararShowDeCenas();
                            }
                          });
                          widget.mostrarFeedback("Cena removida!");
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ] else ...[
          const SizedBox(height: 12),
          const Center(
            child: Text(
              "Nenhuma cena gravada. Regule os faders acima e salve!",
              style: TextStyle(color: Colors.white30, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }
}