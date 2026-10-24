/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/version.dart';
import 'package:musify/ongaku/brand.dart';
import 'package:musify/ongaku/l10n/ongaku_strings.dart';
import 'package:musify/utilities/url_launcher.dart';
import 'package:musify/widgets/shapes/four_sided_cookie_shape.dart';

/// About page header: Ongaku's banner, the version,
/// Orikami's card with the GitHub link, and the fork notice.
class OngakuAboutHeader extends StatelessWidget {
  const OngakuAboutHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 8),
        const _Banner('assets/icons/ongaku_banner.png'),
        const SizedBox(height: 14),
        _VersionChip(),
        const SizedBox(height: 24),
        OngakuCreditCard(
          leading: Text(
            'O',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: colorScheme.onPrimary,
            ),
          ),
          name: ongakuAuthor,
          role: strings.aboutOngakuRole,
          actions: [
            OngakuCreditButton(
              icon: FluentIcons.code_24_filled,
              tooltip: ongakuRepoUrl == null ? strings.comingSoon : 'GitHub',
              url: ongakuRepoUrl,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            strings.aboutFork,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

/// About page: Musify's banner, above the card of its author.
class OngakuUpstreamHeader extends StatelessWidget {
  const OngakuUpstreamHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => launchURL(Uri.parse(upstreamUrl)),
          child: const _Banner('assets/icons/musify_banner.png'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Musify's author, as in Musify's About page.
class OngakuUpstreamAuthorCard extends StatelessWidget {
  const OngakuUpstreamAuthorCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = Text(
      'V',
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: colorScheme.onPrimary,
      ),
    );
    return OngakuCreditCard(
      leading: Image.network(
        'https://avatars.githubusercontent.com/u/79704324?v=4',
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => initial,
      ),
      name: 'Valeri Gokadze',
      role: OngakuStrings.of(context).aboutOriginalRole,
      actions: const [
        OngakuCreditButton(
          icon: FluentIcons.code_24_filled,
          tooltip: 'GitHub',
          url: 'https://github.com/gokadzev',
        ),
        OngakuCreditButton(
          icon: FluentIcons.globe_24_filled,
          tooltip: 'Website',
          url: 'https://gokadzev.github.io',
        ),
      ],
    );
  }
}

/// A 3:1 banner with rounded corners.
class _Banner extends StatelessWidget {
  const _Banner(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 3,
        child: Image.asset(asset, fit: BoxFit.cover),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        'v$appVersion',
        style: TextStyle(
          color: colorScheme.onSecondaryContainer,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// A person credited on the About page, with round link buttons.
class OngakuCreditCard extends StatelessWidget {
  const OngakuCreditCard({
    super.key,
    required this.leading,
    required this.name,
    required this.role,
    this.actions = const [],
  });

  final Widget leading;
  final String name;
  final String role;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 52,
                height: 52,
                color: colorScheme.primary,
                alignment: Alignment.center,
                child: leading,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    role,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            for (final action in actions) ...[
              const SizedBox(width: 8),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// Square link button of a credit card; dimmed while [url] is not known.
class OngakuCreditButton extends StatelessWidget {
  const OngakuCreditButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.url,
  });

  final IconData icon;
  final String tooltip;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final url = this.url;
    return Opacity(
      opacity: url == null ? 0.4 : 1,
      child: Material(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: url == null ? null : () => launchURL(Uri.parse(url)),
          borderRadius: BorderRadius.circular(12),
          child: Tooltip(
            message: tooltip,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: colorScheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Financer le projet": Orikami first, then Musify's creator.
class OngakuSponsorCards extends StatelessWidget {
  const OngakuSponsorCards({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = OngakuStrings.of(context);
    return Column(
      children: [
        _SponsorCard(
          name: ongakuAuthor,
          role: ongakuSponsorUrl == null
              ? '$appName · ${strings.comingSoon}'
              : strings.aboutOngakuRole,
          url: ongakuSponsorUrl,
        ),
        _SponsorCard(
          name: 'Valeri Gokadze',
          role: strings.aboutOriginalRole,
          url: upstreamSponsorUrl,
        ),
      ],
    );
  }
}

class _SponsorCard extends StatelessWidget {
  const _SponsorCard({
    required this.name,
    required this.role,
    required this.url,
  });

  final String name;
  final String role;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final url = this.url;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: url == null ? null : () => launchURL(Uri.parse(url)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              FourSidedCookieShape(
                size: 44,
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.14),
                child: Icon(
                  FluentIcons.drink_coffee_24_filled,
                  color: colorScheme.onPrimaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      role,
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (url != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
