import 'dart:convert';
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

  final void Function(String cmd, String val) enviarComando;
  final void Function(String msg) mostrarFeedback;
  final void Function(Map<String, dynamic> cena) dispararCena;
  final void Function() iniciarShowDeCenas;
  final void Function() pararShowDeCenas;
  final void Function(double val) setTempoTransicaoShow;
  final void Function(List<Map<String, dynamic>> novasCenas) setCenasSalvas;

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
  final TextEditingController _nomeCenaController = TextEditingController();

  void _salvarCenaAtual() {
    String nome = _nomeCenaController.text.trim();
    if (nome.isEmpty) {
      widget.mostrarFeedback("⚠️ Digite um nome para a cena.");
      return;
    }

    final novaCena = {
      'nome': nome,
      'faders': List<double>.from(widget.fadersDMX8),
      'modo': widget.modoAtual,
      'vel': widget.velocidad,
      'dim': widget.brilhoGeral,
      'brilhos': List<double>.from(widget.brilhoCanaisManuais),
      'velocidades': List<double>.from(widget.velocidadesCanaisManuais),
    };

    List<Map<String, dynamic>> atualizadas = List.from(widget.cenasSalvas)..add(novaCena);
    widget.setCenasSalvas(atualizadas);
    _nomeCenaController.clear();
    Navigator.of(context).pop();
    widget.mostrarFeedback("✅ Cena '$nome' gravada com sucesso!");
  }

  void _mostrarDialogSalvar() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text("SALVAR CENA ATUAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        content: TextField(
          controller: _nomeCenaController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Nome da Cena (ex: Show Inicial)",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.deepOrangeAccent)),
          ),
        ),
        actions: [
          TextButton(
            child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrangeAccent, foregroundColor: Colors.black),
            onPressed: _salvarCenaAtual,
            child: const Text("SALVAR"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Título e Botão de Salvar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("MESA DMX (8 CANAIS)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.0)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrangeAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text("Salvar Cena", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _mostrarDialogSalvar,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Faders DMX8
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(8, (index) {
                  return Expanded(
                    child: Column(
                      children: [
                        Text("${index + 1}", style: const TextStyle(color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              value: widget.fadersDMX8[index],
                              min: 0.0,
                              max: 100.0,
                              activeColor: Colors.deepOrangeAccent,
                              inactiveColor: Colors.white12,
                              onChanged: (val) {
                                setState(() {
                                  widget.fadersDMX8[index] = val;
                                });
                                widget.enviarComando("SET_CH${index + 1}", "${val.round()}");
                              },
                            ),
                          ),
                        ),
                        Text("${widget.fadersDMX8[index].round()}%", style: const TextStyle(color: Colors.white54, fontSize: 9)),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Painel do Sequenciador de Cenas (Show)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("SEQUENCIADOR AUTOMÁTICO (SHOW)", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.0)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Tempo de Transição: ${widget.tempoTransicaoShow.toStringAsFixed(1)}s",
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: Slider(
                        value: widget.tempoTransicaoShow,
                        min: 1.0,
                        max: 10.0,
                        divisions: 18,
                        activeColor: Colors.deepOrangeAccent,
                        onChanged: (val) {
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
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[800]),
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text("INICIAR SHOW", style: TextStyle(fontSize: 11)),
                        onPressed: widget.executandoShow ? null : widget.iniciarShowDeCenas,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
                        icon: const Icon(Icons.stop, size: 16),
                        label: const Text("PARAR SHOW", style: TextStyle(fontSize: 11)),
                        onPressed: !widget.executandoShow ? null : widget.pararShowDeCenas,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Lista de Cenas Salvas
          if (widget.cenasSalvas.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text("CENAS GRAVADAS", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.0)),
            const SizedBox(height: 6),
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.cenasSalvas.length,
                itemBuilder: (context, index) {
                  final cena = widget.cenasSalvas[index];
                  final bool ativa = widget.executandoShow && widget.indiceCenaShow == index;
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      backgroundColor: ativa ? Colors.deepOrangeAccent : const Color(0xFF141414),
                      side: const BorderSide(color: Colors.white10),
                      label: Text(
                        cena['nome'],
                        style: TextStyle(
                          color: ativa ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      onPressed: () {
                        widget.dispararCena(cena);
                        widget.mostrarFeedback("🎬 Disparada cena: ${cena['nome']}");
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}