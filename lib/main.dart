//main.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Add this import for kIsWeb
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/location_service.dart';
import 'services/supabase_service.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/signup_screen.dart';
import 'admin/dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  String supabaseUrl;
  String supabaseAnonKey;
  
  if (kIsWeb) {
    // For web builds, use compile-time environment variables
    supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
    supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
    
    // Add validation for web builds
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw Exception('SUPABASE_URL and SUPABASE_ANON_KEY must be provided for web builds');
    }
  } else {
    // For mobile builds, use dotenv
    await dotenv.load(fileName: ".env");
    supabaseUrl = dotenv.env['SUPABASE_URL']!;
    supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;
  }
  
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => SupabaseService()),
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
      child: MaterialApp(
        title: 'Alert to Divert',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.red,
          scaffoldBackgroundColor: Colors.white,
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const AuthWrapper(),
          '/login': (context) => LoginScreen(),
          '/signup': (context) => SignupScreen(),
          '/main': (context) => AuthGuard(child: MainScreen()),
          '/admin': (context) => AuthGuard(child: AdminDashboard()),
        },
      ),
    );
  }
}

class AuthGuard extends StatefulWidget {
  final Widget child;
  const AuthGuard({Key? key, required this.child}) : super(key: key);

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // ✅ Fix: Use addPostFrameCallback to defer navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuth();
    });
  }

  Future<void> _checkAuth() async {
    if (!mounted) return;

    final authService = Provider.of<AuthService>(context, listen: false);

    // Get current session
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
      return;
    }

    // Load user role if not loaded yet
    if (authService.userRole == null) {
      await authService.loadUserRole();
    }

    if (!mounted) return;

    // Role-based navigation
    if (widget.child is AdminDashboard && authService.userRole != 'Administrator') {
      Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
      return;
    }

    if (widget.child is MainScreen && authService.userRole == 'Administrator') {
      Navigator.of(context).pushNamedAndRemoveUntil('/admin', (route) => false);
      return;
    }

    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.child;
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // ✅ Fix: Use addPostFrameCallback to defer navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAuth();
    });
  }

  Future<void> _initAuth() async {
    if (!mounted) return;

    final authService = Provider.of<AuthService>(context, listen: false);

    // Check current session
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      // Load role from Supabase
      if (authService.userRole == null) {
        await authService.loadUserRole();
      }

      if (!mounted) return;

      // Navigate based on role
      if (authService.userRole == 'Administrator') {
        Navigator.of(context).pushNamedAndRemoveUntil('/admin', (route) => false);
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
      }
    } else {
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox.shrink();
  }
}