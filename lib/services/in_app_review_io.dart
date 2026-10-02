// Native (Android/iOS) implementation for in-app review
import 'package:in_app_review/in_app_review.dart';

Future<void> requestNativeReview() async {
  final inAppReview = InAppReview.instance;
  if (await inAppReview.isAvailable()) {
    await inAppReview.requestReview();
  }
}

Future<void> openNativeStoreListing() async {
  final inAppReview = InAppReview.instance;
  await inAppReview.openStoreListing(appStoreId: 'com.hastveda.app');
}
