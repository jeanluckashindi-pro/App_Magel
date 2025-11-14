import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';

// ============================================================================
// CONFIGURATION
// ============================================================================
class AppConfig {
  static const String baseUrl = 'https://apps.mediabox.bi:8020';
  static const String authEndpoint = '/api/login/fa2a3293-533b-4788-a2f0-0b04f7fdf260';
  static const String meetingsEndpoint = '/reunion/';
  static const String presenceEndpoint = '/reunion_presence/';
  static const String presenceCountEndpoint = '/nb_presence_by_reunion/';
  static const String allPresencesEndpoint = '/reunion_presence/';
  static const int requestTimeout = 100;
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ============================================================================
// MODELS
// ============================================================================
class Meeting {
  final int id;
  final String code;
  final String title;
  final String location;
  final String startTime;
  final String endTime;
  final DateTime date;
  final String status;
  final String? secretary;
  final String? comment;
  final String? fileUrl;
  final int type;
  final DateTime createdAt;

  Meeting({
    required this.id,
    required this.code,
    required this.title,
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.date,
    required this.status,
    this.secretary,
    this.comment,
    this.fileUrl,
    required this.type,
    required this.createdAt,
  });

  factory Meeting.fromJson(Map<String, dynamic> json) {
    DateTime dateTime;
    try {
      final dateStr = json['date_reunion']?.toString() ?? '';
      final timeStr = json['heure_debut']?.toString() ?? '00:00';
      if (dateStr.isNotEmpty) {
        dateTime = DateTime.parse('$dateStr $timeStr');
      } else {
        dateTime = DateTime.now();
      }
    } catch (e) {
      dateTime = DateTime.now();
    }

    return Meeting(
      id: json['id'] ?? 0,
      code: json['code_reunion']?.toString() ?? '',
      title: json['titre']?.toString() ?? 'Sans titre',
      location: json['lieu_reunion']?.toString() ?? '',
      startTime: json['heure_debut']?.toString() ?? '00:00',
      endTime: json['heure_fin']?.toString() ?? '00:00',
      date: dateTime,
      status: json['id_statut']?['description']?.toString() ?? 'Planifiée',
      secretary: json['id_secretaire']?['DESCRIPTION']?.toString(),
      comment: json['commentaire']?.toString(),
      fileUrl: json['upload_file']?.toString(),
      type: json['type_reunion'] ?? 1,
      createdAt: DateTime.parse(json['date_insertion']?.toString() ?? DateTime.now().toString()),
    );
  }

  String get formattedDate => DateFormat('dd MMM yyyy', 'fr_FR').format(date);
  String get formattedTime => startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
  String get duration {
    final start = startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
    final end = endTime.length >= 5 ? endTime.substring(0, 5) : endTime;
    return '$start - $end';
  }

  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  bool get isUpcoming {
    final now = DateTime.now();
    return date.isAfter(now) || isToday;
  }

  bool get isPast {
    final now = DateTime.now();
    return date.isBefore(DateTime(now.year, now.month, now.day));
  }

  bool get hasSecretary => secretary != null && secretary!.isNotEmpty;

  String get dynamicStatus {
    final now = DateTime.now();
    final meetingStart = DateTime(date.year, date.month, date.day,
        int.parse(startTime.split(':')[0]), int.parse(startTime.split(':')[1]));
    final meetingEnd = DateTime(date.year, date.month, date.day,
        int.parse(endTime.split(':')[0]), int.parse(endTime.split(':')[1]));
    if (now.isBefore(meetingStart)) return 'Planifiée';
    if (now.isAfter(meetingStart) && now.isBefore(meetingEnd)) return 'En cours';
    return 'Terminée';
  }

  Color get statusColor {
    switch (dynamicStatus.toLowerCase()) {
      case 'planifiée': return const Color(0xFF2196F3);
      case 'en cours': return const Color(0xFF4CAF50);
      case 'terminée': return const Color(0xFF9C27B0);
      default: return Colors.grey;
    }
  }
}

class Presence {
  final int id;
  final int reunionId;
  final int profilId;
  final int fonctionId;
  final int userId;
  final String dateInsertion;
  final String? profilDescription;
  final String? fonctionDescription;
  final String? userNom;
  final String? userPrenom;
  final String? userEmail;
  final String? userTelephone;

  Presence({
    required this.id,
    required this.reunionId,
    required this.profilId,
    required this.fonctionId,
    required this.userId,
    required this.dateInsertion,
    this.profilDescription,
    this.fonctionDescription,
    this.userNom,
    this.userPrenom,
    this.userEmail,
    this.userTelephone,
  });

  factory Presence.fromJson(Map<String, dynamic> json) {
    return Presence(
      id: json['id'] ?? 0,
      reunionId: json['reunion_id'] is Map ? json['reunion_id']['id'] : json['reunion_id'],
      profilId: json['profil_id'] is Map ? json['profil_id']['PROFIL_ID'] : json['profil_id'],
      fonctionId: json['fonction_id'] is Map ? json['fonction_id']['id'] : json['fonction_id'],
      userId: json['id_user'] is Map ? json['id_user']['ADMIN_ID'] : json['id_user'],
      dateInsertion: json['date_insertion']?.toString() ?? '',
      profilDescription: json['profil_id'] is Map ? json['profil_id']['DESCRIPTION']?.toString() : null,
      fonctionDescription: json['fonction_id'] is Map ? json['fonction_id']['description']?.toString() : null,
      userNom: json['id_user'] is Map ? json['id_user']['NOM']?.toString() : null,
      userPrenom: json['id_user'] is Map ? json['id_user']['PRENOM']?.toString() : null,
      userEmail: json['id_user'] is Map ? json['id_user']['EMAIL_PRO']?.toString() : null,
      userTelephone: json['id_user'] is Map ? json['id_user']['TELEPHONE']?.toString() : null,
    );
  }

  String get fullName {
    if (userNom != null && userPrenom != null) return '$userNom $userPrenom';
    if (userNom != null) return userNom!;
    if (userPrenom != null) return userPrenom!;
    return 'Utilisateur $userId';
  }

  String get formattedTime {
    try {
      final timeStr = dateInsertion.split(' ').last;
      return timeStr.length >= 8 ? timeStr.substring(0, 8) : timeStr;
    } catch (e) {
      return dateInsertion;
    }
  }
}

class ScannedParticipant {
  final String code;
  final String name;
  final String email;
  final DateTime scannedAt;

  ScannedParticipant({
    required this.code,
    required this.name,
    required this.email,
    required this.scannedAt,
  });
}

class UserInfo {
  final int profilId;
  final int fonctionId;
  final int adminId;
  final int idUser;

  UserInfo({
    required this.profilId,
    required this.fonctionId,
    required this.adminId,
    required this.idUser,
  });

  factory UserInfo.fromToken(Map<String, dynamic> token) {
    return UserInfo(
      profilId: token['PROFIL_ID'] ?? 0,
      fonctionId: token['fonction_id'] ?? 0,
      adminId: token['ADMIN_ID'] ?? 0,
      idUser: token['ADMIN_ID'] ?? 0,
    );
  }
}

// ============================================================================
// MAIN
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFFE53935),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MeetingProvider()),
      ],
      child: MaterialApp(
        title: 'Mediabox Présence',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: ThemeData(
          fontFamily: 'Roboto',
          colorScheme: const ColorScheme.light(
            primary: Color(0xFFE53935),
            secondary: Color(0xFFFFB300),
            tertiary: Color(0xFF43A047),
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F7FA),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
          ),
          appBarTheme: const AppBarTheme(
            elevation: 0,
            backgroundColor: Color(0xFFE53935),
            foregroundColor: Colors.white,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

// ============================================================================
// SPLASH SCREEN
// ============================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const AuthWrapper(),
            transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE53935), Color(0xFFFF6F00)],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, 10))],
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded, size: 80, color: Color(0xFFE53935)),
                  ),
                  const SizedBox(height: 32),
                  const Text('MAGEL SCANNER', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  const Text('Engineered by MediaBox', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w300)),
                  const SizedBox(height: 50),
                  const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white), strokeWidth: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// AUTH WRAPPER
// ============================================================================
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return auth.isAuthenticated ? const MeetingSelectionScreen() : const LoginScreen();
      },
    );
  }
}

// ============================================================================
// AUTH PROVIDER
// ============================================================================
class AuthProvider with ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  bool _isAuthenticated = false;
  bool _isLoading = true;
  String? _accessToken;
  String? _userEmail;
  UserInfo? _userInfo;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get accessToken => _accessToken;
  String? get userEmail => _userEmail;
  UserInfo? get userInfo => _userInfo;

  AuthProvider() {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final token = await _storage.read(key: 'access_token');
      final email = await _storage.read(key: 'user_email');
      if (token != null && email != null) {
        _accessToken = token;
        _userEmail = email;
        _userInfo = _decodeToken(token);
        _isAuthenticated = true;
      }
    } catch (e) {
      debugPrint('Erreur vérification token: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  UserInfo? _decodeToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return UserInfo.fromToken(jsonDecode(payload));
    } catch (e) {
      debugPrint('Erreur décodage token: $e');
      return null;
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      final uri = Uri.parse('${AppConfig.baseUrl}${AppConfig.authEndpoint}');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({"LOG_IN": email.trim(), "password": password}),
      ).timeout(const Duration(seconds: AppConfig.requestTimeout));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access'];
        _userEmail = email.trim();
        _userInfo = _decodeToken(_accessToken!);
        await _storage.write(key: 'access_token', value: _accessToken);
        await _storage.write(key: 'refresh_token', value: data['refresh']);
        await _storage.write(key: 'user_email', value: _userEmail);
        _isAuthenticated = true;
        notifyListeners();
        return true;
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Identifiants incorrects');
      }
    } on TimeoutException {
      throw Exception('Timeout: Serveur non accessible');
    } on http.ClientException {
      throw Exception('Erreur de connexion réseau');
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    _isAuthenticated = false;
    _accessToken = null;
    _userEmail = null;
    _userInfo = null;
    notifyListeners();
  }
}

// ============================================================================
// MEETING PROVIDER
// ============================================================================
class MeetingProvider with ChangeNotifier {
  List<Meeting> _meetings = [];
  Meeting? _selectedMeeting;
  final List<ScannedParticipant> _participants = [];
  bool _isLoading = false;
  String? _error;
  int _presenceCount = 0;
  final List<Presence> _presences = [];
  bool _isLoadingPresences = false;
  final Set<int> _scannedUserIds = {};

  List<Meeting> get meetings => _meetings;
  Meeting? get selectedMeeting => _selectedMeeting;
  List<ScannedParticipant> get participants => _participants;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get presenceCount => _presenceCount;
  List<Presence> get presences => _presences;
  bool get isLoadingPresences => _isLoadingPresences;

  void selectMeeting(Meeting meeting) {
    _selectedMeeting = meeting;
    _participants.clear();
    _presenceCount = 0;
    _scannedUserIds.clear();
    notifyListeners();
    _fetchPresenceCount(meeting.id);
    _fetchPresences(meeting.id);
  }

  bool hasUserAlreadyScanned(int userId) => _scannedUserIds.contains(userId);
  void addScannedUser(int userId) => _scannedUserIds.add(userId);

  Future<void> fetchMeetings(String token) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final uri = Uri.parse('${AppConfig.baseUrl}${AppConfig.meetingsEndpoint}?page=1&page_size=50&expand=id_statut,id_secretaire');
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: AppConfig.requestTimeout));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _meetings = (data['results'] as List).map((json) => Meeting.fromJson(json)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Session expirée. Veuillez vous reconnecter.');
      } else {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }
    } on TimeoutException {
      _error = 'Timeout: Serveur non accessible';
    } on http.ClientException {
      _error = 'Erreur de connexion réseau';
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchPresenceCount(int reunionId) async {
    try {
      final uri = Uri.parse('${AppConfig.baseUrl}${AppConfig.presenceCountEndpoint}?reunion_id=$reunionId');
      final token = Provider.of<AuthProvider>(navigatorKey.currentContext!, listen: false).accessToken;
      if (token == null) return;
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: AppConfig.requestTimeout));
      if (response.statusCode == 200) {
        _presenceCount = jsonDecode(response.body)['nb_presence'] ?? 0;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erreur count: $e');
    }
  }

  Future<void> _fetchPresences(int reunionId) async {
    _isLoadingPresences = true;
    notifyListeners();
    try {
      final uri = Uri.parse('${AppConfig.baseUrl}${AppConfig.allPresencesEndpoint}?reunion_id=$reunionId');
      final token = Provider.of<AuthProvider>(navigatorKey.currentContext!, listen: false).accessToken;
      if (token == null) return;
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: AppConfig.requestTimeout));
      if (response.statusCode == 200) {
        final results = (jsonDecode(response.body)['results'] as List? ?? []);
        _presences.clear();
        _scannedUserIds.clear();
        for (var json in results) {
          final p = Presence.fromJson(json);
          _presences.add(p);
          _scannedUserIds.add(p.userId);
        }
        _presences.sort((a, b) => b.dateInsertion.compareTo(a.dateInsertion));
      }
    } catch (e) {
      debugPrint('Erreur fetch presences: $e');
    } finally {
      _isLoadingPresences = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> sendPresence({
    required int reunionId,
    required UserInfo adminInfo,
    required int scannedUserId,
  }) async {
    if (hasUserAlreadyScanned(scannedUserId)) {
      return {'success': false, 'message': 'Présence déjà marquée', 'isDuplicate': true};
    }

    try {
      final uri = Uri.parse('${AppConfig.baseUrl}${AppConfig.presenceEndpoint}');
      final token = Provider.of<AuthProvider>(navigatorKey.currentContext!, listen: false).accessToken;
      if (token == null) return {'success': false, 'message': 'Token manquant'};

      final body = {
        "profil_id": adminInfo.profilId,
        "fonction_id": adminInfo.fonctionId,
        "id_user": scannedUserId,
        "reunion_id": reunionId,
      };

      final response = await http.post(
        uri,
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: AppConfig.requestTimeout));

      if (response.statusCode == 201 || response.statusCode == 200) {
        addScannedUser(scannedUserId);
        await _fetchPresenceCount(reunionId);
        await _fetchPresences(reunionId);
        return {'success': true, 'message': 'Présence enregistrée'};
      } else if (response.statusCode == 400) {
        final errorData = jsonDecode(response.body);
        final msg = errorData['message'] ?? errorData['detail'] ?? 'Erreur';
        return {'success': false, 'message': msg, 'isDuplicate': msg.toLowerCase().contains('existe')};
      } else {
        return {'success': false, 'message': 'Erreur serveur: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Erreur réseau'};
    }
  }

  List<Meeting> get upcomingMeetings => _meetings.where((m) => m.isUpcoming || m.isToday).toList()..sort((a, b) => a.date.compareTo(b.date));
  List<Meeting> get pastMeetings => _meetings.where((m) => !m.isUpcoming && !m.isToday).toList()..sort((a, b) => b.date.compareTo(a.date));
}

// ============================================================================
// LOGIN SCREEN
// ============================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animController);
    _animController.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final success = await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
      if (success && mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MeetingSelectionScreen()));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE53935), Color(0xFFD32F2F)]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: const Color(0xFFE53935).withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.qr_code_2_rounded, size: 64, color: Color(0xFFE53935)),
                          ),
                          const SizedBox(height: 24),
                          const Text('Mediabox Présence', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Connectez-vous à votre compte', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              prefixIcon: const Icon(Icons.email_outlined),
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Email requis' : (!v.contains('@') ? 'Email invalide' : null),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passCtrl,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Mot de passe',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Mot de passe requis' : (v.length < 3 ? 'Mot de passe trop court' : null),
                          ),
                          const SizedBox(height: 12),
                          if (_error != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                              child: Row(children: [const Icon(Icons.error_outline, color: Colors.red, size: 20), const SizedBox(width: 8), Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red)))]),
                            ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _login,
                              child: _loading
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('Se connecter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// MEETING SELECTION SCREEN
// ============================================================================
class MeetingSelectionScreen extends StatefulWidget {
  const MeetingSelectionScreen({super.key});
  @override
  State<MeetingSelectionScreen> createState() => _MeetingSelectionScreenState();
}

class _MeetingSelectionScreenState extends State<MeetingSelectionScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMeetings());
  }

  Future<void> _loadMeetings() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final meetingProvider = Provider.of<MeetingProvider>(context, listen: false);
    if (auth.accessToken == null) {
      await auth.logout();
      return;
    }
    try {
      await meetingProvider.fetchMeetings(auth.accessToken!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 3)));
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(margin: const EdgeInsets.only(bottom: 16), height: 140, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
      ),
    );
  }

  Widget _buildMeetingList(List<Meeting> meetings, {required bool isEmpty}) {
    if (isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.event_busy, size: 80, color: Colors.grey[400]), const SizedBox(height: 16), Text('Aucune réunion', style: TextStyle(fontSize: 18, color: Colors.grey[600]))]));
    }
    return RefreshIndicator(
      onRefresh: _loadMeetings,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: meetings.length,
        itemBuilder: (context, index) => _MeetingCard(
          meeting: meetings[index],
          onTap: () {
            final provider = Provider.of<MeetingProvider>(context, listen: false);
            provider.selectMeeting(meetings[index]);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFE53935), Color(0xFFFF5722)])),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.meeting_room, color: Colors.white)),
                            const SizedBox(width: 12),
                            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('MAGEL', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), Text('Scanner les participants', style: TextStyle(color: Colors.white70, fontSize: 14))])),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: const [Tab(icon: Icon(Icons.schedule), text: "Pour Aujourd'hui"), Tab(icon: Icon(Icons.history), text: 'Récentes')],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  final auth = Provider.of<AuthProvider>(context, listen: false);
                  await auth.logout();
                  if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
                },
              ),
            ],
          ),
        ],
        body: Consumer<MeetingProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) return _buildSkeletonList();
            if (provider.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Text('Erreur: ${provider.error}', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey[700]))),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _loadMeetings, child: const Text('Réessayer')),
                  ],
                ),
              );
            }
            return TabBarView(
              controller: _tabController,
              children: [
                _buildMeetingList(provider.upcomingMeetings, isEmpty: provider.upcomingMeetings.isEmpty),
                _buildMeetingList(provider.pastMeetings, isEmpty: provider.pastMeetings.isEmpty),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// MEETING CARD
// ============================================================================
class _MeetingCard extends StatelessWidget {
  final Meeting meeting;
  final VoidCallback onTap;
  const _MeetingCard({required this.meeting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MeetingProvider>(context);
    final isSelected = provider.selectedMeeting?.id == meeting.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isSelected ? Border.all(color: const Color(0xFFE53935), width: 2) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [meeting.statusColor.withOpacity(0.1), meeting.statusColor.withOpacity(0.05)]), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.meeting_room, color: meeting.statusColor, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(meeting.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: meeting.statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(meeting.status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: meeting.statusColor)),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF43A047), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.check, color: Colors.white, size: 20))
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFE53935), Color(0xFFD32F2F)]), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 24),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: meeting.isToday ? const Color(0xFFFFB300).withOpacity(0.1) : Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Icon(meeting.isToday ? Icons.today : Icons.event, size: 18, color: meeting.isToday ? const Color(0xFFFFB300) : Colors.blue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(meeting.isToday ? "Aujourd'hui" : meeting.formattedDate, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(meeting.duration, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      if (isSelected) Text('${provider.presenceCount} présent(s)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF43A047))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 8),
                    Expanded(child: Text(meeting.location, style: TextStyle(fontSize: 14, color: Colors.grey[700]), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                      child: Text(meeting.code, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[700], fontFamily: 'monospace')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCANNER SCREEN
// ============================================================================
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  MobileScannerController? _controller;
  bool _hasScanned = false;
  bool _flashOn = false;
  bool _isSending = false;
  bool _isScannerReady = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, facing: CameraFacing.back, torchEnabled: false);
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _isScannerReady = true));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

Future<void> _handleScan(BarcodeCapture capture, Meeting meeting, UserInfo adminInfo) async {
  if (_hasScanned || _isSending) return;

  final barcode = capture.barcodes.firstWhere(
    (b) => b.rawValue != null && b.rawValue!.trim().isNotEmpty,
    orElse: () => Barcode(rawValue: '', format: BarcodeFormat.unknown),
  );

  final qrData = barcode.rawValue!.trim();
  if (qrData.isEmpty) return;

  int? scannedUserId;

  // 1. Format EMP-MAG-XX
  final empMagMatch = RegExp(r'EMP[\s-]*MAG[\s-]*(\d+)', caseSensitive: false).firstMatch(qrData);
  if (empMagMatch != null) {
    scannedUserId = int.tryParse(empMagMatch.group(1)!);
  }
  // 2. ID brut
  else if (int.tryParse(qrData) != null) {
    scannedUserId = int.parse(qrData);
  }
  // 3. JSON
  else {
    try {
      final json = jsonDecode(qrData);
      scannedUserId = json['id_user'] ?? json['idUser'] ?? json['user_id'];
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR Code invalide'), backgroundColor: Colors.red),
      );
      return;
    }
  }

  if (scannedUserId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ID utilisateur non trouvé'), backgroundColor: Colors.red),
    );
    return;
  }

  // CONDITION CORRIGÉE : EMP-MAG-XX toujours valide
  final isEmpMag = RegExp(r'EMP[\s-]*MAG[\s-]*\d+', caseSensitive: false).hasMatch(qrData);
  if (!isEmpMag) {
    final hasMeetingId = qrData.contains(meeting.id.toString());
    final hasMeetingCode = meeting.code.isNotEmpty && qrData.contains(meeting.code);
    if (!hasMeetingId && !hasMeetingCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR Code non valide pour cette réunion'), backgroundColor: Colors.orange),
      );
      return;
    }
  }

  setState(() => _hasScanned = true);
  _controller?.stop();
  HapticFeedback.mediumImpact();

  setState(() => _isSending = true);
  final result = await Provider.of<MeetingProvider>(context, listen: false).sendPresence(
    reunionId: meeting.id,
    adminInfo: adminInfo,
    scannedUserId: scannedUserId,
  );
  setState(() => _isSending = false);

  final color = result['success'] == true
      ? const Color(0xFF43A047)
      : (result['isDuplicate'] == true ? Colors.orange : Colors.red);

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result['message']), backgroundColor: color),
    );
  }

  await Future.delayed(const Duration(milliseconds: 1500));
  setState(() => _hasScanned = false);
  if (mounted) _controller?.start();
}
  void _showParticipantsList() {
    final provider = Provider.of<MeetingProvider>(context, listen: false);
    final meeting = provider.selectedMeeting;
    if (meeting == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey))),
              child: Row(
                children: [
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFE53935).withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.people, color: Color(0xFFE53935))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Liste des présences', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('${provider.presenceCount} participant(s)', style: TextStyle(fontSize: 14, color: Colors.grey[600]))])),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            if (provider.isLoadingPresences)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (provider.presences.isEmpty)
              Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people_outline, size: 80, color: Colors.grey[400]), const SizedBox(height: 16), Text('Aucune présence enregistrée', style: TextStyle(fontSize: 16, color: Colors.grey[600]))])))
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.presences.length,
                  itemBuilder: (context, index) {
                    final presence = provider.presences[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
                      child: Row(
                        children: [
                          Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFE53935).withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.person, color: const Color(0xFFE53935), size: 20)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(presence.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                if (presence.fonctionDescription != null) Text(presence.fonctionDescription!, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                                if (presence.userEmail != null) Text(presence.userEmail!, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(presence.formattedTime, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFF43A047).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text('Présent', style: TextStyle(fontSize: 10, color: const Color(0xFF43A047), fontWeight: FontWeight.bold))),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meetingProvider = Provider.of<MeetingProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final meeting = meetingProvider.selectedMeeting;
    if (meeting == null) {
      return Scaffold(appBar: AppBar(title: const Text('Erreur')), body: const Center(child: Text('Aucune réunion sélectionnée')));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_controller != null && _isScannerReady)
            MobileScanner(controller: _controller!, onDetect: (capture) => _handleScan(capture, meeting, authProvider.userInfo!)),
          const ModernScannerOverlay(),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 40, left: 16, right: 16, bottom: 16),
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.7), Colors.transparent])),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(meeting.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${meetingProvider.presenceCount} présent(s)', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.list, color: Colors.white), onPressed: _showParticipantsList),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ScanButton(icon: _flashOn ? Icons.flash_on : Icons.flash_off, label: 'Flash', isActive: _flashOn, onPressed: () { setState(() => _flashOn = !_flashOn); _controller?.toggleTorch(); }),
                _ScanButton(icon: Icons.flip_camera_ios, label: 'Caméra', onPressed: () => _controller?.switchCamera()),
                _ScanButton(icon: Icons.close, label: 'Terminer', onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          if (_isSending)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Envoi en cours...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// SCAN BUTTON
// ============================================================================
class _ScanButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isActive;
  const _ScanButton({required this.icon, required this.label, required this.onPressed, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(color: Colors.white.withOpacity(isActive ? 1.0 : 0.9), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]),
          child: IconButton(icon: Icon(icon, color: const Color(0xFFE53935), size: 28), onPressed: onPressed),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ============================================================================
// SCANNER OVERLAY
// ============================================================================
class ModernScannerOverlay extends StatefulWidget {
  const ModernScannerOverlay({super.key});
  @override
  State<ModernScannerOverlay> createState() => _ModernScannerOverlayState();
}

class _ModernScannerOverlayState extends State<ModernScannerOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: Colors.black.withOpacity(0.5)),
        Center(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.3), width: 2)),
            child: Stack(
              children: [
                ...[const Alignment(-1, -1), const Alignment(1, -1), const Alignment(-1, 1), const Alignment(1, 1)].map((alignment) => Align(
                      alignment: alignment,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border(
                            top: alignment.y < 0 ? const BorderSide(color: Color(0xFFE53935), width: 4) : BorderSide.none,
                            left: alignment.x < 0 ? const BorderSide(color: Color(0xFFE53935), width: 4) : BorderSide.none,
                            bottom: alignment.y > 0 ? const BorderSide(color: Color(0xFFE53935), width: 4) : BorderSide.none,
                            right: alignment.x > 0 ? const BorderSide(color: Color(0xFFE53935), width: 4) : BorderSide.none,
                          ),
                        ),
                      ),
                    )),
                AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    return Positioned(top: 20 + (_animation.value * 240), left: 20, right: 20, child: Container(height: 2, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.transparent, Color(0xFFE53935), Color(0xFFE53935), Colors.transparent]), boxShadow: [BoxShadow(color: const Color(0xFFE53935).withOpacity(0.5), blurRadius: 10)])));
                  },
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 160,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20)),
              child: const Text('Placez le QR code dans le cadre', style: TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ),
        ),
      ],
    );
  }
}