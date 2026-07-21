import 'package:flutter/material.dart';

class OfflineStatusService {
  OfflineStatusService._();

  static final OfflineStatusService instance = OfflineStatusService._();

  final ValueNotifier<bool> isOffline = ValueNotifier<bool>(false);

  void markOffline() {
    if (!isOffline.value) isOffline.value = true;
  }

  void markOnline() {
    if (isOffline.value) isOffline.value = false;
  }
}

class OfflineStatusBanner extends StatelessWidget {
  const OfflineStatusBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: OfflineStatusService.instance.isOffline,
      builder: (context, offline, _) {
        return Stack(
          children: [
            child,
            if (offline)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.paddingOf(context).top,
                child: IgnorePointer(
                  child: Material(
                    color: const Color(0xFFF59E0B),
                    elevation: 4,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 5, horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off_rounded,
                              size: 15, color: Colors.black),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Offline — showing saved information',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
