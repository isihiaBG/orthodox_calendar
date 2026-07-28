// typikon_legend_sheet.dart
//
// Справка за петте знака на типика (богослужебния ранг на деня) плюс
// обяснение за деня без знак. Отваря се от тап върху самия знак в
// дневния изглед — виж showTypikonLegendSheet(). Изградена върху общия
// info_sheet.dart инструмент (заглавие + регулируем шрифт + списък).

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';
import 'info_sheet.dart';

Widget _iconOrDot(String? iconPath, Color color) {
  return iconPath != null
      ? SvgPicture.asset(
          iconPath,
          width: 20,
          height: 20,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        )
      : Center(
          child: Text('•',
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              )),
        );
}

void showTypikonLegendSheet(BuildContext context) {
  final items = [
    InfoSheetItem(
      leading: _iconOrDot(AppIcons.tipikonCircleCross, AppColors.signRed),
      title: 'Велик празник',
      description: 'Най-високият ранг — дванадесетте велики Господски и '
          'Богородични празници, както и Обрезание. Прилага се '
          'най-тържественият чин на празнично богослужение.',
    ),
    InfoSheetItem(
      leading: _iconOrDot(AppIcons.tipikonSemiCircle, AppColors.signRed),
      title: 'Бдение',
      description: 'Светия или празник, честван с всенощно бдение — '
          'вечерня, съединена с утренята, часовете и литургията, '
          'продължаващи и през нощта.',
    ),
    InfoSheetItem(
      leading: _iconOrDot(AppIcons.tipikonCross, AppColors.signRed),
      title: 'Полиелей',
      description: 'Празнична служба с полиелей — тържественото пеене на '
          '134-и и 135-и псалом ("Хвалите Имя Господне") на утренята.',
    ),
    InfoSheetItem(
      leading: _iconOrDot(AppIcons.tipikonThreeDots, AppColors.signRed),
      title: 'Славословие',
      description: 'На утренята се пее (не се чете) великото славословие — '
          'по-тържествен чин от обикновения делничен ред, но по-скромен от '
          'полиелейния.',
    ),
    InfoSheetItem(
      leading: _iconOrDot(AppIcons.tipikonThreeDots, AppColors.signWhite),
      title: 'Шестерична служба',
      description: 'Последният ранг със собствен знак — на вечернята '
          'се пеят шест стихири (оттам и името). Службата остава в рамките '
          'на обикновения делничен ред.',
    ),
    InfoSheetItem(
      leading: _iconOrDot(null, AppColors.textMuted),
      title: 'Без знак',
      description: 'Обикновен делничен празник — паметта на светията '
          'се отбелязва без допълнителни тържествени елементи в службата.',
    ),
  ];

  showInfoSheet(
    context: context,
    title: 'Знаци според Типикона',
    subtitle: 'Богослужебният ранг на празника, обозначаван от древност в '
        'църковния типик, валиден и до днес.',
    items: items,
  );
}
