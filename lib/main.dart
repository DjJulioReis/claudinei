import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Controle MILETO',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.amber,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.amberAccent,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// --- TELA DE ABERTURA (SPLASH SCREEN COM LOGO) ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/mileto_logo.png',
              width: 180,
              height: 180,
              errorBuilder: (context, error, stackTrace) {
                return const Text(
                  "MILETO",
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                    letterSpacing: 4.0,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                color: Colors.amber,
                backgroundColor: Colors.white10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int modoAtual = 0;
  double velocidad = 100;
  double brilhoGeral = 100;
  int enderecoDMX = 1;
  bool modoDMX = false;

  BluetoothConnection? _connection;
  bool _isConectado = false;
  bool _isCarregando = false;
  final String _nomeDispositivoAlvo = "MILETO";

  // --- SISTEMA DE SENHA ---
  bool _painelLiberado = false;
  final String _senhaCorreta = "1234";
  final TextEditingController _senhaController = TextEditingController();

  List<String> modosLista = [];
  String _bufferDadosIncompletos = "";

  // --- CONTROLE TELEMÉTRICO DA PISTA (DIRETO DO ESP32) ---
  int tamanhoGrade = 4;
  bool executandoEfeito = false;
  List<double> niveisReaisCanais = [0.0, 0.0, 0.0, 0.0];

  // --- VALORES DOS CANAIS MANUAIS ---
  List<double> brilhoCanaisManuais = [100.0, 100.0, 100.0, 100.0];

  int get totalPlacas => tamanhoGrade * tamanhoGrade;
  int get totalCanais => 4;

  @override
  void initState() {
    super.initState();
    _inicializarEConectarBluetooth();
  }

  void _inicializarPistaLeds() {
    setState(() {
      executandoEfeito = false;
      niveisReaisCanais = [0.0, 0.0, 0.0, 0.0];
      brilhoCanaisManuais = [100.0, 100.0, 100.0, 100.0];
    });
  }

  @override
  void dispose() {
    _connection?.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _inicializarEConectarBluetooth() async {
    setState(() {
      _isCarregando = true;
      modosLista.clear();
      _painelLiberado = false;
    });

    try {
      List<BluetoothDevice> bondedDevices = await FlutterBluetoothSerial.instance.getBondedDevices();
      BluetoothDevice? dispositivoMileto;

      for (var device in bondedDevices) {
        if (device.name == _nomeDispositivoAlvo) {
          dispositivoMileto = device;
          break;
        }
      }

      if (dispositivoMileto != null) {
        BluetoothConnection connection = await BluetoothConnection.toAddress(dispositivoMileto.address);

        setState(() {
          _connection = connection;
          _isCarregando = false;
        });

        _connection!.input?.listen((data) {
          _bufferDadosIncompletos += utf8.decode(data);

          while (_bufferDadosIncompletos.contains('\n')) {
            int posicaoQuebra = _bufferDadosIncompletos.indexOf('\n');
            String linhaComando = _bufferDadosIncompletos.substring(0, posicaoQuebra).trim();
            _bufferDadosIncompletos = _bufferDadosIncompletos.substring(posicaoQuebra + 1);

            if (linhaComando.isEmpty) continue;

            if (linhaComando.startsWith("CH_LEVELS:")) {
              String dados = linhaComando.replaceAll("CH_LEVELS:", "");
              List<String> niveis = dados.split(",");
              if (niveis.length >= 4) {
                setState(() {
                  niveisReaisCanais = List.generate(4, (i) => double.tryParse(niveis[i]) ?? 0.0);
                  executandoEfeito = niveisReaisCanais.any((v) => v > 0);
                });
              }
            }
            else if (linhaComando.contains("CONNECTED_OK")) {
              setState(() => _isConectado = true);
              _mostrarFeedback("MILETO Conectada! Insira a senha de acesso.");
              enviarComando("GET_CAPABILITIES", "1");
            }
            else if (linhaComando.startsWith("CAPS:")) {
              String listaEfeitos = linhaComando.replaceAll("CAPS:", "");
              setState(() {
                modosLista = listaEfeitos.split(",");
              });
            }
            else if (linhaComando.startsWith("CHAVE_MODO:")) {
              String modoVindoDaPlaca = linhaComando.replaceAll("CHAVE_MODO:", "");
              setState(() {
                modoDMX = (modoVindoDaPlaca == "DMX");
              });
              _mostrarFeedback(modoDMX ? "Modo Alterado: Mesa DMX" : "Modo Alterado: Controle Bluetooth");
            }
            else if (linhaComando.contains("[MEMORIA]") || linhaComando.contains("GRAVAR:OK")) {
              _mostrarFeedback("💾 Configurações gravadas com sucesso!");
            }
          }
        }).onDone(() {
          setState(() {
            _isConectado = false;
            _connection = null;
            modosLista.clear();
            _bufferDadosIncompletos = "";
            _painelLiberado = false;
            _inicializarPistaLeds();
          });
          _mostrarFeedback("A placa foi desconectada.");
        });

        enviarComando("PING", "1");

      } else {
        _mostrarFeedback("Dispositivo 'MILETO' não pareado!");
        setState(() => _isCarregando = false);
      }
    } catch (e) {
      _mostrarFeedback("Falha na conexão física do rádio.");
      setState(() {
        _isConectado = false;
        _isCarregando = false;
        modosLista.clear();
        _bufferDadosIncompletos = "";
        _painelLiberado = false;
      });
    }
  }

  void enviarComando(String comando, String valor) async {
    String bufferCompleto = "$comando:$valor\n";
    if (_connection != null && _connection!.isConnected) {
      _connection!.output.add(utf8.encode(bufferCompleto));
      await _connection!.output.allSent;
    }
  }

  void _solicitarTesteDisparo() {
    enviarComando("EFEITO_PISTA", "START");
  }

  void _solicitarApagarPista() {
    enviarComando("EFEITO_PISTA", "CLEAR");
  }

  void _mostrarFeedback(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _verificarSenha() {
    if (_senhaController.text == _senhaCorreta) {
      setState(() {
        _painelLiberado = true;
      });
      _senhaController.clear();
      _mostrarFeedback("🔓 Acesso liberado com sucesso!");
    } else {
      _senhaController.clear();
      _mostrarFeedback("❌ Senha incorreta! Tente novamente.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/mileto_logo.png',
          height: 35,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Text(
                "MILETO",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 18, letterSpacing: 1.5)
            );
          },
        ),
        actions: [
          _isCarregando
              ? const Padding(
            padding: EdgeInsets.all(16.0),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          )
              : IconButton(
            icon: Icon(
              _isConectado ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: _isConectado ? Colors.greenAccent : Colors.redAccent,
            ),
            onPressed: _inicializarEConectarBluetooth,
          )
        ],
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: SafeArea(
        child: !_isConectado
            ? const Center(child: Text("DESCONECTADO\n(TOQUE NO ÍCONE SUPERIOR PARA CONECTAR)", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
            : !_painelLiberado
            ? _buildTelaDeSenha()
            : SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: mediaQuery.padding.bottom + 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    "⚡ LINK ATIVO - RESPONDENDO ⚡",
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Card(
                color: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          modoDMX ? "MODO DMX ATIVO" : "MODO MANUAL / RF",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: modoDMX ? Colors.cyan : Colors.amber),
                        ),
                      ),
                      Switch(
                        value: modoDMX,
                        activeColor: Colors.cyan,
                        inactiveThumbColor: Colors.amber,
                        onChanged: (value) {
                          setState(() {
                            modoDMX = value;
                            enviarComando("CHAVE_MODO", modoDMX ? "DMX" : "RF");
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: modoDMX ? _buildPainelDMX() : _buildPainelManuais(),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.save),
                label: const Text("GRAVAR NA MEMÓRIA", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  enviarComando("GRAVAR", "EEPROM");
                },
              ),
              const SizedBox(height: 24),
              const Center(child: Text("SIMULADOR DE MÓDULOS REAIS", style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 2))),
              const SizedBox(height: 10),
              _buildSimuladorPistaLed(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelaDeSenha() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            const Text(
              "SISTEMA RESTRITO",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              "Digite o PIN de segurança para liberar o console.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _senhaController,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 4,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
              decoration: InputDecoration(
                counterText: "",
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                hintText: "••••",
                hintStyle: const TextStyle(color: Colors.white24),
              ),
              onSubmitted: (_) => _verificarSenha(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _verificarSenha,
                child: const Text("ENTRAR", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPainelDMX() {
    return Card(
      key: const ValueKey(1),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text("CANAL DMX", style: TextStyle(color: Colors.grey)),
            Text("$enderecoDMX", style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.cyan)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly, // <- Corrigido aqui!
              children: [
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.cyan.withOpacity(0.1)),
                  icon: const Icon(Icons.remove, color: Colors.cyan),
                  onPressed: () {
                    setState(() { if (enderecoDMX > 1) enderecoDMX--; });
                    enviarComando("SET_DMX", "$enderecoDMX");
                  },
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.cyan.withOpacity(0.1)),
                  icon: const Icon(Icons.add, color: Colors.cyan),
                  onPressed: () {
                    setState(() { if (enderecoDMX < 512) enderecoDMX++; });
                    enviarComando("SET_DMX", "$enderecoDMX");
                  },
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPainelManuais() {
    bool isEfeitoManualAtivo = modosLista.isNotEmpty &&
        modoAtual < modosLista.length &&
        modosLista[modoAtual].trim().toUpperCase() == "MANUAL";

    return Column(
      key: const ValueKey(2),
      children: [
        Card(
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("EFEITOS MILETO", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                modosLista.isEmpty
                    ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.0),
                    child: Text("Aguardando mapa de efeitos da placa...", style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ),
                )
                    : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: modosLista.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.2),
                  itemBuilder: (context, index) {
                    final bool sel = modoAtual == index;
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: sel ? Colors.amber : const Color(0xFF2E2E2E),
                        foregroundColor: sel ? Colors.black : Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        setState(() => modoAtual = index);
                        enviarComando("SET_MODO", "$modoAtual");
                      },
                      child: Text(modosLista[index], style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (isEfeitoManualAtivo) ...[
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("CONTROLE MANUAL INDEPENDENTE", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 16),
                  ...List.generate(4, (index) {
                    return _buildSliderRow("CANAL ${index + 1}", brilhoCanaisManuais[index], (val) {
                      setState(() => brilhoCanaisManuais[index] = val);
                    }, "SET_CH${index + 1}");
                  }),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (!isEfeitoManualAtivo) ...[
          _buildSliderCard("VELOCIDADE (STROBO / EFEITOS)", velocidad, (val) => setState(() => velocidad = val), "SET_VEL"),
          const SizedBox(height: 8),
          _buildSliderCard("BRILHO GERAL", brilhoGeral, (val) => setState(() => brilhoGeral = val), "SET_DIM"),
        ] else ...[
          _buildSliderCard("VELOCIDADE DA OSCILAÇÃO", velocidad, (val) => setState(() => velocidad = val), "SET_VEL"),
        ],
      ],
    );
  }

  Widget _buildSliderRow(String label, double valor, Function(double) onCh, String cmd) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text("${valor.toInt()}%", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: valor,
              min: 0,
              max: 100,
              divisions: 100,
              activeColor: Colors.amber,
              inactiveColor: Colors.white10,
              onChanged: onCh,
              onChangeEnd: (v) => enviarComando(cmd, "${v.toInt()}"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderCard(String label, double valor, Function(double) onCh, String cmd) {
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                Text("${valor.toInt()}%", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: valor,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: onCh,
              onChangeEnd: (v) => enviarComando(cmd, "${v.toInt()}"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimuladorPistaLed() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("QUANTIDADE DE PLACAS:", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              DropdownButton<int>(
                value: tamanhoGrade,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                underline: Container(height: 2, color: Colors.amber),
                items: [3, 4, 5, 6].map((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text(" Placas (${value}x$value)"),
                  );
                }).toList(),
                onChanged: (novoTamanho) {
                  if (novoTamanho != null) {
                    setState(() {
                      tamanhoGrade = novoTamanho;
                      _solicitarApagarPista();
                    });
                    enviarComando("SET_GRID", "${novoTamanho}x$novoTamanho");
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: 200,
            height: 200,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomPaint(
              size: Size.infinite,
              painter: LedGridPainter(
                gridSize: tamanhoGrade,
                niveisCanais: niveisReaisCanais,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.withOpacity(0.15),
                    foregroundColor: Colors.amber,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.flash_on, size: 18),
                  label: const Text("TESTAR DISPARO", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _solicitarTesteDisparo,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.15),
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text("APAGAR PISTA", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _solicitarApagarPista,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

class LedGridPainter extends CustomPainter {
  final int gridSize;
  final List<double> niveisCanais;

  LedGridPainter({
    required this.gridSize,
    required this.niveisCanais,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int totalPlacas = gridSize * gridSize;
    final double spacing = 6.0;

    final double cellWidth = (size.width - (spacing * (gridSize - 1))) / gridSize;
    final double cellHeight = (size.height - (spacing * (gridSize - 1))) / gridSize;

    final Color corApagado = Colors.grey.shade900;

    // Cores fiéis à imagem (Branco Frio e Branco Quente/Âmbar)
    const Color corBrancoFrio = Color(0xFFE0E8FF);
    const Color corBrancoQuente = Color(0xFFFFE3A3);

    const int pixelsPerSide = 2;
    final double pixelWidth = cellWidth / pixelsPerSide;
    final double pixelHeight = cellHeight / pixelsPerSide;

    for (int i = 0; i < totalPlacas; i++) {
      int rowPlaca = i ~/ gridSize;
      int colPlaca = i % gridSize;

      double xPlaca = colPlaca * (cellWidth + spacing);
      double yPlaca = rowPlaca * (cellHeight + spacing);

      // Determina os canais base da placa (Par: 1/2, Ímpar: 3/4)
      int ch1, ch2;
      if (i % 2 == 0) {
        ch1 = 0; // CH1 -> Frio
        ch2 = 1; // CH2 -> Quente
      } else {
        ch1 = 2; // CH3 -> Frio
        ch2 = 3; // CH4 -> Quente
      }

      final Rect rectPlaca = Rect.fromLTWH(xPlaca, yPlaca, cellWidth, cellHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rectPlaca, const Radius.circular(4)),
        Paint()..color = Colors.black,
      );

      // Continuidade do xadrez global
      bool inverterPlaca = (rowPlaca + colPlaca) % 2 != 0;

      for (int py = 0; py < pixelsPerSide; py++) {
        for (int px = 0; px < pixelsPerSide; px++) {
          bool isPixelA = (px + py) % 2 == 0;
          if (inverterPlaca) isPixelA = !isPixelA;

          int canalIdx = isPixelA ? ch1 : ch2;
          Color corBase = isPixelA ? corBrancoFrio : corBrancoQuente;
          double nivel = niveisCanais[canalIdx] / 100.0;

          double xPixel = xPlaca + (px * pixelWidth);
          double yPixel = yPlaca + (py * pixelHeight);

          final Rect rectPixel = Rect.fromLTWH(xPixel + 1, yPixel + 1, pixelWidth - 2, pixelHeight - 2);

          if (nivel > 0) {
            final Paint pixelPaint = Paint()..color = corBase.withOpacity(nivel.clamp(0.1, 1.0));
            canvas.drawRect(rectPixel, pixelPaint);

            final Paint glow = Paint()
              ..color = corBase.withOpacity(nivel * 0.3)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
            canvas.drawRect(rectPixel.inflate(1), glow);
          } else {
            canvas.drawRect(rectPixel, Paint()..color = corApagado);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant LedGridPainter oldDelegate) {
    return oldDelegate.gridSize != gridSize ||
        oldDelegate.niveisCanais != niveisCanais;
  }
}