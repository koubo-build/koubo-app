import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// 通用卡片组件 - 统一卡片样式
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double borderRadius;
  final double elevation;
  final VoidCallback? onTap;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.borderRadius = AppTheme.radiusMedium,
    this.elevation = 2,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin ?? const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingSmall,
      ),
      color: color ?? AppTheme.darkCard,
      elevation: elevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: border != null
            ? const BorderSide(color: AppTheme.primaryColor, width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(AppTheme.spacingMedium),
          child: child,
        ),
      ),
    );
  }
}

/// 信息展示卡片 - 标题+内容的卡片
class InfoCard extends StatelessWidget {
  final String title;
  final Widget? titleIcon;
  final Widget content;
  final String? trailing;
  final Color? titleColor;
  final VoidCallback? onTap;

  const InfoCard({
    super.key,
    required this.title,
    this.titleIcon,
    required this.content,
    this.trailing,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              if (titleIcon != null) ...[
                IconTheme(
                  data: IconThemeData(
                    color: titleColor ?? AppTheme.primaryColor,
                    size: 20,
                  ),
                  child: titleIcon!,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: titleColor ?? AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (trailing != null)
                Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: 13,
                    color: titleColor ?? AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          // 内容区域
          content,
        ],
      ),
    );
  }
}
