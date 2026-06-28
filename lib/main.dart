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

  // --- VARIÁVEIS BLE ---
  BleDevice? _deviceAlvo;
  bool _isConectado = false;
  bool _isCarregando = false;
  final String _nomeDispositivoAlvo = "MILETO";

  // UUIDs Padrão Nordic UART
  final String _serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String _txUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"; // Notificações (ESP -> App)
  final String _rxUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"; // Escrita (App -> ESP)

  // --- SISTEMA DE SENHA ---
  bool _painelLiberado = false;
  final String _senhaCorreta = "1234";
  final TextEditingController _senhaController = TextEditingController();

  List<String> modosLista = ["MANUAL", "FADE", "STROBO", "SEQUENC", "FIXO"];
  String _bufferDadosIncompletos = "";

  // --- CONTROLE TELEMÉTRICO DA PISTA ---
  int tamanhoGrade = 4;
  bool executandoEfeito = false;
  List<double> niveisReaisCanais = [0.0, 0.0, 0.0, 0.0];

  // --- VALORES DOS CANAIS MANUAIS ---
  int canalManualSelecionado = 1;
  List<double> brilhoCanaisManuais = [100.0, 100.0, 100.0, 100.0];
  List<double> velocidadesCanaisManuais = [100.0, 100.0, 100.0, 100.0];

  @override
  void initState() {
    super.initState();
    _configurarEscutaDeDadosBLE();
    _inicializarEConectarBluetooth();
  }

  void _inicializarPistaLeds() {
    setState(() {
      executandoEfeito = false;
      niveisReaisCanais = [0.0, 0.0, 0.0, 0.0];
      brilhoCanaisManuais = [100.0, 100.0, 100.0, 100.0];
      velocidadesCanaisManuais = [100.0, 100.0, 100.0, 100.0];
    });
  }

  @override
  void dispose() {
    if (_deviceAlvo != null) {
      UniversalBle.disconnect(_deviceAlvo!.deviceId);
    }
    _senhaController.dispose();
    super.dispose();
  }

  // Configura a escuta global do Universal BLE
  void _configurarEscutaDeDadosBLE() {
    // RESOLVIDO: Assinatura correta para o Universal BLE moderno (4 argumentos)
    UniversalBle.onValueChange = (String deviceId, String serviceId, String characteristicId, Uint8List value) {
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
          }
          else if (linha.contains("CONNECTED_OK")) {
            _mostrarFeedback("Conexão validada com a placa!");
            enviarComando("GET_CAPABILITIES", "1");
          }
          else if (linha.startsWith("CAPS:")) {
            setState(() {
              modosLista = linha.replaceAll("CAPS:", "").split(",");
            });
          }
          else if (linha.startsWith("CHAVE_MODO:")) {
            setState(() {
              modoDMX = (linha.replaceAll("CHAVE_MODO:", "") == "DMX");
            });
            _mostrarFeedback(modoDMX ? "Placa em Modo DMX" : "Placa em Modo Manual");
          }
          else if (linha.contains("GRAVAR:OK")) {
            _mostrarFeedback("💾 Configurações salvas com sucesso!");
          }
        }
      }
    };

    UniversalBle.onConnectionChange = (String deviceId, BleConnectionState state) {
      if (_deviceAlvo != null && deviceId == _deviceAlvo!.deviceId) {
        bool isConnected = (state == BleConnectionState.connected);
        setState(() {
          _isConectado = isConnected;
          if (!isConnected) {
            _deviceAlvo = null;
            _bufferDadosIncompletos = "";
            _painelLiberado = false;
            _inicializarPistaLeds();
          }
        });
        if (!isConnected) _mostrarFeedback("MILETO desconectada.");
      }
    };
  }

  Future<void> _inicializarEConectarBluetooth() async {
    if (_isConectado && _deviceAlvo != null) {
      await UniversalBle.disconnect(_deviceAlvo!.deviceId);
      return;
    }

    setState(() {
      _isCarregando = true;
      _painelLiberado = false;
    });

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

        // Ativa notificações no canal TX (Notificações do ESP32 para o App)
        await UniversalBle.setNotifiable(
            _deviceAlvo!.deviceId,
            _serviceUuid,
            _txUuid,
            BleInputProperty.notification
        );

        setState(() {
          _isConectado = true;
          _isCarregando = false;
        });

        _mostrarFeedback("MILETO Conectada via BLE!");
      }
    } catch (e) {
      await UniversalBle.stopScan();
      _mostrarFeedback("Não foi possível conectar à placa.");
      setState(() {
        _isConectado = false;
        _isCarregando = false;
        _bufferDadosIncompletos = "";
        _painelLiberado = false;
      });
    }
  }

  void enviarComando(String comando, String valor) async {
    String buffer = "$comando:$valor\n";
    if (_isConectado && _deviceAlvo != null) {
      try {
        await UniversalBle.writeValue(
            _deviceAlvo!.deviceId,
            _serviceUuid,
            _rxUuid,
            Uint8List.fromList(utf8.encode(buffer)),
            BleOutputProperty.withResponse
        );
      } catch (e) {
        try {
          await UniversalBle.writeValue(
              _deviceAlvo!.deviceId,
              _serviceUuid,
              _rxUuid,
              Uint8List.fromList(utf8.encode(buffer)),
              BleOutputProperty.withoutResponse
          );
        } catch (_) {}
      }
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
      setState(() => _painelLiberado = true);
      _senhaController.clear();
      _mostrarFeedback("🔓 Acesso liberado!");
    } else {
      _senhaController.clear();
      _mostrarFeedback("❌ PIN incorreto.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MILETO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 1.2)),
        actions: [
          _isCarregando
              ? const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
            icon: Icon(_isConectado ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: _isConectado ? Colors.greenAccent : Colors.redAccent),
            onPressed: _inicializarEConectarBluetooth,
          )
        ],
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: SafeArea(
        child: !_isConectado
            ? const Center(child: Text("DESCONECTADO\n(TOQUE NO ÍCONE PARA CONECTAR)", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
            : !_painelLiberado
            ? _buildTelaDeSenha()
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: const Color(0xFF1E1E1E),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        modoDMX ? "MODO DMX ATIVO" : "MODO MANUAL / RF",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: modoDMX ? Colors.cyan : Colors.amber),
                      ),
                      Switch(
                        value: modoDMX,
                        activeColor: Colors.cyan,
                        onChanged: (value) {
                          setState(() => modoDMX = value);
                          enviarComando("CHAVE_MODO", modoDMX ? "DMX" : "RF");
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
                onPressed: () => enviarComando("GRAVAR", "1"),
              ),
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
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.amber),
            const SizedBox(height: 24),
            TextField(
              controller: _senhaController,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 4,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(filled: true, fillColor: const Color(0xFF1E1E1E), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), hintText: "PIN"),
              onSubmitted: (_) => _verificarSenha(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text("ENDEREÇO DMX ATUAL", style: TextStyle(color: Colors.grey)),
            Text("$enderecoDMX", style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.cyan)),
            const Text("(Ajuste via botões físicos)", style: TextStyle(color: Colors.white24, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildPainelManuais() {
    bool isManual = modoAtual == 0;
    return Column(
      children: [
        Card(
          color: const Color(0xFF1E1E1E),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: modosLista.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.2),
              itemBuilder: (context, index) {
                final bool sel = modoAtual == index;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: sel ? Colors.amber : const Color(0xFF2E2E2E), foregroundColor: sel ? Colors.black : Colors.white),
                  onPressed: () {
                    setState(() => modoAtual = index);
                    enviarComando("SET_MODO", "$modoAtual");
                  },
                  child: Text(modosLista[index], style: const TextStyle(fontSize: 11)),
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
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(4, (index) {
                      final int canal = index + 1;
                      final bool sel = canalManualSelecionado == canal;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: index < 3 ? 8 : 0),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: sel ? Colors.amber : const Color(0xFF2E2E2E), foregroundColor: sel ? Colors.black : Colors.white70),
                            onPressed: () => setState(() => canalManualSelecionado = canal),
                            child: Text("CH$canal"),
                          ),
                        ),
                      );
                    }),
                  ),
                  const Divider(height: 32, color: Colors.white10),
                  _buildSliderRow("BRILHO CANAL $canalManualSelecionado", brilhoCanaisManuais[canalManualSelecionado - 1], (val) => setState(() => brilhoCanaisManuais[canalManualSelecionado - 1] = val), "SET_CH$canalManualSelecionado"),
                  _buildSliderRow("VELOCIDADE CANAL $canalManualSelecionado", velocidadesCanaisManuais[canalManualSelecionado - 1], (val) => setState(() => velocidadesCanaisManuais[canalManualSelecionado - 1] = val), "SET_VCH$canalManualSelecionado", icon: Icons.speed),
                ],
              ),
            ),
          ),
        ],
        if (!isManual) ...[
          const SizedBox(height: 8),
          _buildSliderCard("VELOCIDADE DOS EFEITOS", velocidad, (val) => setState(() => velocidad = val), "SET_VEL"),
          const SizedBox(height: 8),
          _buildSliderCard("BRILHO GERAL", brilhoGeral, (val) => setState(() => brilhoGeral = val), "SET_DIM"),
        ],
      ],
    );
  }

  Widget _buildSliderRow(String label, double val, Function(double) onCh, String cmd, {IconData? icon}) {
    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 11)), Text("${val.toInt()}%", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))]),
        Slider(value: val, min: 0, max: 100, divisions: 100, activeColor: Colors.amber, onChanged: onCh, onChangeEnd: (v) => enviarComando(cmd, cmd.contains("VCH") ? "${v.toInt()}" : "${(v/100*255).round()}")),
      ],
    );
  }

  Widget _buildSliderCard(String label, double val, Function(double) onCh, String cmd) {
    return Card(
      color: const Color(0xFF1E1E1E),
      child: Padding(padding: const EdgeInsets.all(12), child: _buildSliderRow(label, val, onCh, cmd)),
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
              const Text("PLACAS REAIS", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              DropdownButton<int>(
                value: tamanhoGrade,
                dropdownColor: const Color(0xFF1E1E1E),
                items: [3, 4, 5, 6].map((int i) => DropdownMenuItem(value: i, child: Text("${i}x$i  "))).toList(),
                onChanged: (v) => setState(() => tamanhoGrade = v!),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(8)),
            child: CustomPaint(painter: LedGridPainter(gridSize: tamanhoGrade, niveisCanais: niveisReaisCanais)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ElevatedButton(onPressed: _solicitarTesteDisparo, child: const Text("TESTAR"))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(onPressed: _solicitarApagarPista, child: const Text("APAGAR"))),
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
  LedGridPainter({required this.gridSize, required this.niveisCanais});
  @override
  void paint(Canvas canvas, Size size) {
    double sw = size.width / gridSize, sh = size.height / gridSize;
    for (int i = 0; i < gridSize * gridSize; i++) {
      int r = i ~/ gridSize, c = i % gridSize;
      int chF = (r + c) % 2 == 0 ? 0 : 2, chQ = (r + c) % 2 == 0 ? 1 : 3;
      double nf = niveisCanais[chF] / 100.0, nq = niveisCanais[chQ] / 100.0;
      final Rect rect = Rect.fromLTWH(c * sw, r * sh, sw - 2, sh - 2);
      if (nf == 0 && nq == 0) {
        canvas.drawRect(rect, Paint()..color = Colors.grey.shade900);
      } else {
        double t = (nf + nq).clamp(0.001, 2.0);
        int red = ((224 * nf + 255 * nq) / t).round();
        int green = ((232 * nf + 227 * nq) / t).round();
        int blue = ((255 * nf + 163 * nq) / t).round();
        canvas.drawRect(rect, Paint()..color = Color.fromARGB(255, red, green, blue).withOpacity((t / 1.5).clamp(0.3, 1.0)));
      }
    }
  }
  @override
  bool shouldRepaint(covariant LedGridPainter old) => old.niveisCanais != niveisCanais || old.gridSize != gridSize;
}
