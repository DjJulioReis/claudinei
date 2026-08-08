import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'conecta.dart';
import 'mileto_motor_sinetico_page.dart';

class ProgramacaoMotoresPage extends StatefulWidget {
  final BleDevice? deviceAlvo;
  final List<MotorCinetico> motoresConectados;
  final Function(String, String) enviarComando;

  const ProgramacaoMotoresPage({
    super.key,
    required this.deviceAlvo,
    required this.motoresConectados,
    required this.enviarComando,
  });

  @override
  State<ProgramacaoMotoresPage> createState() => _ProgramacaoMotoresPageState();
}

class _ProgramacaoMotoresPageState extends State<ProgramacaoMotoresPage> {
  // Cores de blocos disponíveis
  final List<Color> coresBlocos = [
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.red,
  ];

  // Nomes amigáveis dos blocos
  final List<String> nomesBlocos = ["Verde", "Azul", "Roxo", "Vermelho"];

  // Bloco de Cor selecionado para atribuição (Índice correspondente a coresBlocos)
  int blocoAtivoIdx = 0;

  // Mapa relacionando o UID do Motor à cor do bloco atribuída (null = sem bloco/individual)
  Map<String, Color?> blocosMotores = {};

  // Alturas e Velocidades programadas para cada bloco de cor (0-3) - Max 3000 mm (3 metros)
  List<double> alturasBlocos = [1500.0, 1500.0, 1500.0, 1500.0];
  List<double> velocidadesBlocos = [50.0, 50.0, 50.0, 50.0];

  // Altura e velocidade individual caso queira controlar um motor avulso
  double alturaIndividual = 1500.0;
  double velocidadeIndividual = 50.0;
  String? motorSelecionadoIndividualUid;

  @override
  void initState() {
    super.initState();
    // Inicializa todos os motores sem bloco por padrão
    for (var m in widget.motoresConectados) {
      blocosMotores[m.uid] = null;
    }
    if (widget.motoresConectados.isNotEmpty) {
      motorSelecionadoIndividualUid = widget.motoresConectados.first.uid;
    }
  }

  void _dispararComandoBloco(Color corBloco, double altura, double vel) {
    // Filtra os motores que pertencem a este bloco de cor e envia os comandos BLE correspondentes
    for (var motor in widget.motoresConectados) {
      if (blocosMotores[motor.uid] == corBloco) {
        setState(() {
          motor.targetPosMM = altura;
          motor.targetPosition = (altura * 18.0).toInt(); // 18 passos por mm no sistema real
        });
        // Protocolo de envio de posição para o motor RDM correspondente
        widget.enviarComando("SET_POS", "${motor.targetPosition}");
      }
    }
  }

  void _dispararComandoIndividual(MotorCinetico motor, double altura, double vel) {
    setState(() {
      motor.targetPosMM = altura;
      motor.targetPosition = (altura * 18.0).toInt(); // 18 passos por mm no sistema real
    });
    widget.enviarComando("SET_POS", "${motor.targetPosition}");
  }

  @override
  Widget build(BuildContext context) {
    final Color corAtiva = coresBlocos[blocoAtivoIdx];

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text("PROGRAMAÇÃO DE BLOCOS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 14)),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.amber),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ConectaPage()),
            );
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- SELETOR DE BLOCO DE CORES (CLEAN) ---
            Card(
              color: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    const Text(
                      "PASSO 1: ESCOLHA UMA COR E CLIQUE NOS MOTORES PARA CRIAR O BLOCO",
                      style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(coresBlocos.length, (index) {
                        final Color cor = coresBlocos[index];
                        final bool sel = blocoAtivoIdx == index;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              blocoAtivoIdx = index;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? cor.withOpacity(0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: sel ? cor : Colors.white10, width: sel ? 2 : 1),
                              boxShadow: [
                                if (sel)
                                  BoxShadow(color: cor.withOpacity(0.15), blurRadius: 10, spreadRadius: 1),
                              ],
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(backgroundColor: cor, radius: 8),
                                const SizedBox(width: 8),
                                Text(
                                  nomesBlocos[index].toUpperCase(),
                                  style: TextStyle(
                                    color: sel ? Colors.white : Colors.white60,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- GRADE DE PONTOS INTERATIVOS REPRESENTEANDO OS MOTORES ---
            const Text(
              "REDE DE MOTORES KINETIC (TOQUE PARA ATRIBUIR AO BLOCO)",
              style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.motoresConectados.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.0,
                ),
                itemBuilder: (context, index) {
                  final motor = widget.motoresConectados[index];
                  final Color? corAtribuida = blocosMotores[motor.uid];
                  final bool temCor = corAtribuida != null;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        // Se clicar em cima e já tiver aquela cor, tira a cor. Senão, atribui a cor do bloco selecionado!
                        if (blocosMotores[motor.uid] == corAtiva) {
                          blocosMotores[motor.uid] = null;
                        } else {
                          blocosMotores[motor.uid] = corAtiva;
                        }
                      });
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: temCor ? corAtribuida.withOpacity(0.2) : const Color(0xFF1E1E1E),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: temCor ? corAtribuida : Colors.white24,
                              width: temCor ? 2.5 : 1,
                            ),
                            boxShadow: [
                              if (temCor)
                                BoxShadow(color: corAtribuida.withOpacity(0.4), blurRadius: 12, spreadRadius: 2),
                            ],
                          ),
                          child: Icon(
                            Icons.settings_input_composite,
                            color: temCor ? corAtribuida : Colors.grey,
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "CH ${motor.dmxAddress}",
                          style: TextStyle(
                            color: temCor ? corAtribuida : Colors.white30,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // --- CONTROLES DE GRUPO DO BLOCO DE COR ATIVO ---
            Card(
              color: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(backgroundColor: corAtiva, radius: 8),
                        const SizedBox(width: 10),
                        Text(
                          "PROGRAMAR BLOCO ${nomesBlocos[blocoAtivoIdx].toUpperCase()}",
                          style: TextStyle(fontWeight: FontWeight.bold, color: corAtiva, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("ALTURA DO CABO (0 a 3000mm)", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text("${alturasBlocos[blocoAtivoIdx].round()} mm", style: TextStyle(color: corAtiva, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: alturasBlocos[blocoAtivoIdx],
                      min: 0.0,
                      max: 3000.0,
                      divisions: 300,
                      activeColor: corAtiva,
                      onChanged: (val) {
                        setState(() {
                          alturasBlocos[blocoAtivoIdx] = val;
                        });
                        _dispararComandoBloco(corAtiva, val, velocidadesBlocos[blocoAtivoIdx]);
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("VELOCIDADE DOS MOTORES", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text("${velocidadesBlocos[blocoAtivoIdx].round()}%", style: TextStyle(color: corAtiva, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: velocidadesBlocos[blocoAtivoIdx],
                      min: 0.0,
                      max: 100.0,
                      divisions: 100,
                      activeColor: corAtiva,
                      onChanged: (val) {
                        setState(() {
                          velocidadesBlocos[blocoAtivoIdx] = val;
                        });
                        _dispararComandoBloco(corAtiva, alturasBlocos[blocoAtivoIdx], val);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // --- CONTROLES INDIVIDUAIS DE MOTORES SOLTOS ---
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.tune, color: Colors.white60, size: 18),
                        SizedBox(width: 10),
                        Text(
                          "PROGRAMAÇÃO SEPARADA INDIVIDUAL",
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: motorSelecionadoIndividualUid,
                        dropdownColor: const Color(0xFF1A1A1A),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        items: widget.motoresConectados.map((motor) {
                          return DropdownMenuItem<String>(
                            value: motor.uid,
                            child: Text(motor.nome),
                          );
                        }).toList(),
                        onChanged: (novoUid) {
                          setState(() {
                            motorSelecionadoIndividualUid = novoUid;
                            final activeMotor = widget.motoresConectados.firstWhere((m) => m.uid == novoUid);
                            alturaIndividual = activeMotor.targetPosMM;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("ALTURA INDIVIDUAL (0 a 3000mm)", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text("${alturaIndividual.round()} mm", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: alturaIndividual,
                      min: 0.0,
                      max: 3000.0,
                      divisions: 300,
                      activeColor: Colors.amber,
                      onChanged: (val) {
                        setState(() {
                          alturaIndividual = val;
                        });
                        if (motorSelecionadoIndividualUid != null) {
                          final activeMotor = widget.motoresConectados.firstWhere((m) => m.uid == motorSelecionadoIndividualUid);
                          _dispararComandoIndividual(activeMotor, val, velocidadeIndividual);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}