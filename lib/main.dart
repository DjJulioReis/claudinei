import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

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
              errorBuilder: (context, error, stackTrace) => const Text(
                "MILETO",
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 4.0),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(width: 120, child: LinearProgressIndicator(color: Colors.amber, backgroundColor: Colors.white10)),
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

  BleDevice? _deviceAlvo;
  bool _isConectado = false;
  bool _isCarregando = false;
  final String _nomeDispositivoAlvo = "MILETO";

  final String _serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String _txUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"; // RX no App
  final String _rxUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"; // TX no App

  bool _painelLiberado = false;
  final String _senhaCorreta = "1234";
  final TextEditingController _senhaController = TextEditingController();

  List<String> modosLista = ["MANUAL", "FADE", "STROBO", "SEQUENC", "FIXO"];
  String _bufferDadosIncompletos = "";

  int tamanhoGrade = 4;
  bool executandoEfeito = false;
  List<double> niveisReaisCanais = [0.0, 0.0, 0.0, 0.0];

  int canalManualSelecionado = 1;
  List<double> brilhoCanaisManuais = [100.0, 100.0, 100.0, 100.0];
  List<double> velocidadesCanaisManuais = [100.0, 100.0, 100.0, 100.0];

  @override
  void initState() {
    super.initState();
    _configurarEscutaDeDadosBLE();
    _inicializarEConectarBluetooth();
  }

  void _configurarEscutaDeDadosBLE() {
    UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value) {
      if (_deviceAlvo != null && deviceId == _deviceAlvo!.deviceId) {
        _bufferDadosIncompletos += utf8.decode(value);
        while (_bufferDadosIncompletos.contains('\n')) {
          int pos = _bufferDadosIncompletos.indexOf('\n');
          String linha = _bufferDadosIncompletos.substring(0, pos).trim();
          _bufferDadosIncompletos = _bufferDadosIncompletos.substring(pos + 1);
          if (linha.isEmpty) continue;

          if (linha.startsWith("CH_LEVELS:")) {
            List<String> n = linha.replaceAll("CH_LEVELS:", "").split(",");
            if (n.length >= 4) {
              setState(() {
                niveisReaisCanais = List.generate(4, (i) => double.tryParse(n[i]) ?? 0.0);
                executandoEfeito = niveisReaisCanais.any((v) => v > 0);
              });
            }
          } else if (linha.contains("CONNECTED_OK")) {
            _mostrarFeedback("Link BLE autenticado!");
          } else if (linha.startsWith("CAPS:")) {
            setState(() => modosLista = linha.replaceAll("CAPS:", "").split(","));
          } else if (linha.startsWith("CHAVE_MODO:")) {
            setState(() => modoDMX = (linha.replaceAll("CHAVE_MODO:", "") == "DMX"));
          } else if (linha.contains("GRAVAR:OK")) {
            _mostrarFeedback("💾 Configurações salvas!");
          }
        }
      }
    };

    UniversalBle.onConnectionChange = (String deviceId, bool isConnected, String? error) {
      if (_deviceAlvo != null && deviceId == _deviceAlvo!.deviceId) {
        setState(() {
          _isConectado = isConnected;
          if (!isConnected) {
            _deviceAlvo = null;
            _painelLiberado = false;
          }
        });
      }
    };
  }

  Future<void> _inicializarEConectarBluetooth() async {
    if (_isConectado && _deviceAlvo != null) {
      await UniversalBle.disconnect(_deviceAlvo!.deviceId);
      return;
    }
    setState(() { _isCarregando = true; _painelLiberado = false; });
    try {
      await UniversalBle.startScan();
      Completer<BleDevice> c = Completer();
      UniversalBle.onScanResult = (device) {
        if (device.name == _nomeDispositivoAlvo || device.name?.contains("MILETO") == true) {
          if (!c.isCompleted) c.complete(device);
        }
      };
      _deviceAlvo = await c.future.timeout(const Duration(seconds: 10));
      await UniversalBle.stopScan();
      if (_deviceAlvo != null) {
        await UniversalBle.connect(_deviceAlvo!.deviceId);
        await UniversalBle.discoverServices(_deviceAlvo!.deviceId);
        await UniversalBle.setNotifiable(_deviceAlvo!.deviceId, _serviceUuid, _txUuid, BleInputProperty.notification);
        setState(() { _isConectado = true; _isCarregando = false; });
        _mostrarFeedback("MILETO Conectada!");
        enviarComando("GET_CAPABILITIES", "1");
      }
    } catch (e) {
      await UniversalBle.stopScan();
      setState(() { _isConectado = false; _isCarregando = false; });
      _mostrarFeedback("Erro ao conectar BLE.");
    }
  }

  void enviarComando(String cmd, String val) async {
    if (_isConectado && _deviceAlvo != null) {
      String data = "$cmd:$val\n";
      try {
        await UniversalBle.writeValue(_deviceAlvo!.deviceId, _serviceUuid, _rxUuid, Uint8List.fromList(utf8.encode(data)), BleOutputProperty.withResponse);
      } catch (_) {
        await UniversalBle.writeValue(_deviceAlvo!.deviceId, _serviceUuid, _rxUuid, Uint8List.fromList(utf8.encode(data)), BleOutputProperty.withoutResponse);
      }
    }
  }

  void _mostrarFeedback(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _verificarSenha() {
    if (_senhaController.text == _senhaCorreta) { setState(() => _painelLiberado = true); _senhaController.clear(); }
    else { _senhaController.clear(); _mostrarFeedback("❌ Senha incorreta!"); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MILETO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
        actions: [
          if (_isCarregando) const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else IconButton(icon: Icon(_isConectado ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: _isConectado ? Colors.greenAccent : Colors.redAccent), onPressed: _inicializarEConectarBluetooth)
        ],
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: SafeArea(
        child: !_isConectado ? const Center(child: Text("DESCONECTADO", style: TextStyle(color: Colors.grey)))
            : !_painelLiberado ? _buildTelaDeSenha()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Card(
                      color: const Color(0xFF1E1E1E),
                      child: ListTile(
                        title: Text(modoDMX ? "MODO DMX ATIVO" : "MODO MANUAL", style: TextStyle(fontWeight: FontWeight.bold, color: modoDMX ? Colors.cyan : Colors.amber)),
                        trailing: Switch(value: modoDMX, onChanged: (v) { setState(() => modoDMX = v); enviarComando("CHAVE_MODO", modoDMX ? "DMX" : "RF"); }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: modoDMX ? _buildPainelDMX() : _buildPainelManuais()),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)), icon: const Icon(Icons.save), label: const Text("GRAVAR NA MEMÓRIA"), onPressed: () => enviarComando("GRAVAR", "1")),
                    const SizedBox(height: 24),
                    _buildSimuladorPistaLed(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTelaDeSenha() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            TextField(controller: _senhaController, obscureText: true, keyboardType: TextInputType.number, textAlign: TextAlign.center, maxLength: 4, decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1E1E1E), hintText: "PIN")),
            const SizedBox(height: 16),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, minimumSize: const Size(double.infinity, 50)), onPressed: _verificarSenha, child: const Text("ENTRAR")),
          ],
        ),
      ),
    );
  }

  Widget _buildPainelDMX() {
    return Card(color: const Color(0xFF1E1E1E), child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [const Text("DMX ADDRESS"), Text("$enderecoDMX", style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.cyan))])));
  }

  Widget _buildPainelManuais() {
    bool isManual = modoAtual == 0;
    return Column(
      children: [
        Card(
          color: const Color(0xFF1E1E1E),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: modosLista.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.2, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemBuilder: (c, i) => ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: modoAtual == i ? Colors.amber : const Color(0xFF2E2E2E)),
                onPressed: () { setState(() => modoAtual = i); enviarComando("SET_MODO", "$i"); },
                child: Text(modosLista[i], style: const TextStyle(fontSize: 10)),
              ),
            ),
          ),
        ),
        if (isManual) ...[
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1E1E1E),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(4, (i) => ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: canalManualSelecionado == i + 1 ? Colors.amber : const Color(0xFF2E2E2E)), onPressed: () => setState(() => canalManualSelecionado = i + 1), child: Text("CH${i + 1}")))),
                  _buildSlider("BRILHO CH$canalManualSelecionado", brilhoCanaisManuais[canalManualSelecionado - 1], (v) => setState(() => brilhoCanaisManuais[canalManualSelecionado - 1] = v), "SET_CH$canalManualSelecionado"),
                  _buildSlider("VELOC CH$canalManualSelecionado", velocidadesCanaisManuais[canalManualSelecionado - 1], (v) => setState(() => velocidadesCanaisManuais[canalManualSelecionado - 1] = v), "SET_VCH$canalManualSelecionado"),
                ],
              ),
            ),
          ),
        ],
        if (!isManual) ...[
          _buildSlider("VELOCIDADE", velocidad, (v) => setState(() => velocidad = v), "SET_VEL"),
          _buildSlider("BRILHO GERAL", brilhoGeral, (v) => setState(() => brilhoGeral = v), "SET_DIM"),
        ],
      ],
    );
  }

  Widget _buildSlider(String label, double val, Function(double) onCh, String cmd) {
    return Column(children: [Text(label), Slider(value: val, min: 0, max: 100, divisions: 100, activeColor: Colors.amber, onChanged: onCh, onChangeEnd: (v) => enviarComando(cmd, cmd.startsWith("SET_VCH") || cmd == "SET_VEL" ? "${v.toInt()}" : "${(v / 100 * 255).round()}"))]);
  }

  Widget _buildSimuladorPistaLed() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("PLACAS:"), DropdownButton<int>(value: tamanhoGrade, items: [3, 4, 5, 6].map((i) => DropdownMenuItem(value: i, child: Text("${i}x$i"))).toList(), onChanged: (v) { if (v != null) setState(() => tamanhoGrade = v); })]),
          Container(width: 200, height: 200, color: Colors.black, child: CustomPaint(painter: LedGridPainter(gridSize: tamanhoGrade, niveisCanais: niveisReaisCanais))),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: ElevatedButton(onPressed: () => enviarComando("EFEITO_PISTA", "START"), child: const Text("TESTAR"))), const SizedBox(width: 8), Expanded(child: ElevatedButton(onPressed: () => enviarComando("EFEITO_PISTA", "CLEAR"), child: const Text("APAGAR")))]),
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
      int chF = (r + c) % 2 == 0 ? 0 : 2, chQ = (r + c) % 2 == 0 ? 1 : 3;
      double nf = niveisCanais[chF] / 100, nq = niveisCanais[chQ] / 100;
      if (nf == 0 && nq == 0) { canvas.drawRect(Rect.fromLTWH(c * sw, r * sh, sw - 2, sh - 2), Paint()..color = Colors.grey.shade900); }
      else {
        double t = nf + nq;
        int red = ((224 * nf + 255 * nq) / t).round(), green = ((232 * nf + 227 * nq) / t).round(), blue = ((255 * nf + 163 * nq) / t).round();
        canvas.drawRect(Rect.fromLTWH(c * sw, r * sh, sw - 2, sh - 2), Paint()..color = Color.fromARGB(255, red, green, blue).withOpacity((t / 1).clamp(0.2, 1.0)));
      }
    }
  }
  @override
  bool shouldRepaint(covariant LedGridPainter old) => old.niveisCanais != niveisCanais || old.gridSize != gridSize;
}
