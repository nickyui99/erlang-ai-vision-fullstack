import 'package:http/http.dart' as http;

import 'backend_http_client_stub.dart'
    if (dart.library.html) 'backend_http_client_web.dart'
    as client_factory;

http.Client createBackendHttpClient() =>
    client_factory.createBackendHttpClient();
