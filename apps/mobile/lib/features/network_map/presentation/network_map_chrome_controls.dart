import 'package:flutter/material.dart';

import '../../../accessible_design.dart';

class NetworkMapLookupToast extends StatelessWidget {
  const NetworkMapLookupToast({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Material(
        key: const Key('networkMapNearbyLookupMessage'),
        color: const Color(0xE62F3437),
        elevation: 0,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: EasySubwayAccessibleColors.interactionOnPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class NetworkMapCurrentLocationButton extends StatelessWidget {
  const NetworkMapCurrentLocationButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '현재 위치에서 가장 가까운 역 찾기',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          key: const Key('nearbyStationButton'),
          color: EasySubwayAccessibleColors.surfaceDefault,
          elevation: 0,
          shape: const CircleBorder(
            side: BorderSide(
              color: EasySubwayAccessibleColors.borderSubtle,
              width: 1,
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                Icons.my_location,
                size: 27,
                color: EasySubwayAccessibleColors.contentSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
