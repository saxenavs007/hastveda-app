import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'local_image.dart';

/// Public Cloudflare R2 host for HastVeda images and downloads.
const String kAssetCdnOrigin = 'https://download.hastveda.co';

/// Turns a root-relative or scheme-less CDN path into an absolute URL.
/// Bundled Flutter assets (`assets/...`) are left unchanged.
String resolveMediaUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty || url.startsWith('assets/')) return url;
  if (url.startsWith('https://') || url.startsWith('http://')) return url;
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('download.hastveda.co/') || url == 'download.hastveda.co') {
    return 'https://$url';
  }
  if (url.startsWith('/')) return '$kAssetCdnOrigin$url';
  return url;
}

extension ImageTypeExtension on String {
  ImageType get imageType {
    final resolved = resolveMediaUrl(this);
    if (resolved.startsWith('https://') ||
        resolved.startsWith('http://') ||
        resolved.startsWith('blob:')) {
      return ImageType.network;
    }
    if (toLowerCase().endsWith('.svg')) return ImageType.svg;
    if (startsWith('file:') || startsWith('file://')) return ImageType.file;
    return ImageType.png;
  }
}

enum ImageType { svg, png, network, file, unknown }

/// Gold mark shown while an image is loading and when it cannot be shown.
class ImagePlaceholder extends StatelessWidget {
  const ImagePlaceholder({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final shortest = width != null && height != null
        ? (width! < height! ? width! : height!)
        : 48.0;
    final iconSize = shortest.isFinite ? (shortest * 0.42).clamp(18.0, 42.0) : 28.0;
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF16161C),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: const Color(0xFFD4AF37),
        size: iconSize,
      ),
    );
  }
}

class CustomImageWidget extends StatelessWidget {
  const CustomImageWidget({
    super.key,
    this.imageUrl,
    this.height,
    this.width,
    this.color,
    this.fit,
    this.alignment,
    this.onTap,
    this.radius,
    this.margin,
    this.border,
    this.placeHolder = '',
    this.errorWidget,
    this.semanticLabel,
  });

  final String? imageUrl;
  final double? height;
  final double? width;
  final BoxFit? fit;
  final String placeHolder;
  final Color? color;
  final Alignment? alignment;
  final VoidCallback? onTap;
  final BorderRadius? radius;
  final EdgeInsetsGeometry? margin;
  final BoxBorder? border;
  final Widget? errorWidget;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = _buildWidget();
    return alignment != null ? Align(alignment: alignment!, child: image) : image;
  }

  Widget _buildWidget() {
    final image = Padding(
      padding: margin ?? EdgeInsets.zero,
      child: _buildCircleImage(),
    );
    if (onTap == null) return image;
    return InkWell(onTap: onTap, child: image);
  }

  Widget _buildCircleImage() {
    if (radius != null) {
      return ClipRRect(
        borderRadius: radius ?? BorderRadius.zero,
        child: _buildImageWithBorder(),
      );
    }
    return _buildImageWithBorder();
  }

  Widget _buildImageWithBorder() {
    if (border != null) {
      return Container(
        decoration: BoxDecoration(border: border, borderRadius: radius),
        child: _buildImageView(),
      );
    }
    return _buildImageView();
  }

  Widget _mark() =>
      errorWidget ?? ImagePlaceholder(width: width, height: height);

  Widget _frame(BuildContext context, Widget child, int? frame, bool sync) {
    if (sync || frame != null) return child;
    return _mark();
  }

  Widget _asset(String path) {
    return Image.asset(
      path,
      height: height,
      width: width,
      fit: fit ?? BoxFit.cover,
      color: color,
      semanticLabel: semanticLabel,
      frameBuilder: _frame,
      errorBuilder: (_, __, ___) => _mark(),
    );
  }

  Widget _network(String url) {
    return Image.network(
      url,
      height: height,
      width: width,
      fit: fit,
      color: color,
      semanticLabel: semanticLabel,
      // CanvasKit fetches bytes and needs CORS. An <img> element still
      // paints the picture when R2 does not send Access-Control-Allow-Origin.
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      frameBuilder: _frame,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _mark();
      },
      errorBuilder: (_, __, ___) {
        if (placeHolder.isNotEmpty) return _asset(placeHolder);
        return _mark();
      },
    );
  }

  Widget _buildImageView() {
    final raw = imageUrl?.trim() ?? '';
    if (raw.isEmpty) return _mark();
    final resolved = resolveMediaUrl(raw);

    switch (raw.imageType) {
      case ImageType.svg:
        return SizedBox(
          height: height,
          width: width,
          child: SvgPicture.asset(
            raw,
            height: height,
            width: width,
            fit: fit ?? BoxFit.contain,
            colorFilter: color != null
                ? ColorFilter.mode(color ?? Colors.transparent, BlendMode.srcIn)
                : null,
            semanticsLabel: semanticLabel,
            placeholderBuilder: (_) => _mark(),
            errorBuilder: (_, __, ___) => _mark(),
          ),
        );
      case ImageType.file:
        final path = raw.startsWith('file://') ? raw.substring(7) : raw;
        if (kIsWeb) return _network(resolved);
        return buildLocalFileImage(
          path: path,
          height: height,
          width: width,
          fit: fit,
          color: color,
          semanticLabel: semanticLabel,
          fallback: _mark(),
        );
      case ImageType.network:
        return _network(resolved);
      case ImageType.png:
      case ImageType.unknown:
        return _asset(raw);
    }
  }
}
