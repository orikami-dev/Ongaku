/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/ongaku/widgets/ongaku_credits.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n!.about)),
      body: const SingleChildScrollView(
        padding: commonSingleChildScrollViewPadding,
        child: Column(
          children: <Widget>[
            // Ongaku: Ongaku and Orikami first, then Musify and its author.
            OngakuAboutHeader(),
            OngakuUpstreamHeader(),
            OngakuUpstreamAuthorCard(),
            MiniPlayerBottomSpace(),
          ],
        ),
      ),
    );
  }
}
