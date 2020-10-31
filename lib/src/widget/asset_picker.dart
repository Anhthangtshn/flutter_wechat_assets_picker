///
/// [Author] Alex (https://github.com/Alex525)
/// [Date] 2020/3/31 15:39
///

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/constants.dart';

@immutable
class AssetPicker<A, P> extends StatelessWidget {
  const AssetPicker({
    Key key,
    @required this.builder,
  })  : assert(
          builder != null,
          'Builder must be provided and not null.',
        ),
        super(key: key);

  final AssetPickerBuilderDelegate<A, P> builder;

  /// Static method to push with the navigator.
  /// 跳转至选择器的静态方法
  static Future<List<AssetEntity>> pickAssets(
    BuildContext context, {
    int maxAssets = 9,
    int pageSize = 320,
    int pathThumbSize = 200,
    int gridCount = 4,
    List<int> previewThumbSize,
    RequestType requestType,
    SpecialPickerType specialPickerType,
    List<AssetEntity> selectedAssets,
    Color themeColor,
    ThemeData pickerTheme,
    SortPathDelegate sortPathDelegate,
    AssetsPickerTextDelegate textDelegate,
    FilterOptionGroup filterOptions,
    WidgetBuilder customItemBuilder,
    CustomItemPosition customItemPosition = CustomItemPosition.none,
    Curve routeCurve = Curves.easeIn,
    Duration routeDuration = const Duration(milliseconds: 300),
  }) async {
    if (maxAssets == null || maxAssets < 1) {
      throw ArgumentError(
        'maxAssets must be greater than 1.',
      );
    }
    if (pageSize != null && pageSize % gridCount != 0) {
      throw ArgumentError(
        'pageSize must be a multiple of gridCount.',
      );
    }
    if (pickerTheme != null && themeColor != null) {
      throw ArgumentError(
        'Theme and theme color cannot be set at the same time.',
      );
    }
    if (specialPickerType != null && requestType != null) {
      throw ArgumentError(
        'specialPickerType and requestType cannot be set at the same time.',
      );
    } else {
      if (specialPickerType == SpecialPickerType.wechatMoment) {
        requestType = RequestType.common;
      } else {
        requestType ??= RequestType.image;
      }
    }
    if ((customItemBuilder == null &&
            customItemPosition != CustomItemPosition.none) ||
        (customItemBuilder != null &&
            customItemPosition == CustomItemPosition.none)) {
      throw ArgumentError('Custom item didn\'t set properly.');
    }

    try {
      final bool isPermissionGranted = await PhotoManager.requestPermission();
      if (isPermissionGranted) {
        final DefaultAssetPickerProvider provider = DefaultAssetPickerProvider(
          maxAssets: maxAssets,
          pageSize: pageSize,
          pathThumbSize: pathThumbSize,
          selectedAssets: selectedAssets,
          requestType: requestType,
          sortPathDelegate: sortPathDelegate,
          filterOptions: filterOptions,
          routeDuration: routeDuration,
        );
        final Widget picker = AssetPicker<AssetEntity, AssetPathEntity>(
          key: Constants.pickerKey,
          builder: DefaultAssetPickerBuilderDelegate(
            provider: provider,
            gridCount: gridCount,
            textDelegate: textDelegate,
            themeColor: themeColor,
            pickerTheme: pickerTheme,
            previewThumbSize: previewThumbSize,
            specialPickerType: specialPickerType,
            customItemPosition: customItemPosition,
            customItemBuilder: customItemBuilder,
          ),
        );
        final List<AssetEntity> result = await Navigator.of(
          context,
          rootNavigator: true,
        ).push<List<AssetEntity>>(
          SlidePageTransitionBuilder<List<AssetEntity>>(
            builder: picker,
            transitionCurve: routeCurve,
            transitionDuration: routeDuration,
          ),
        );
        return result;
      } else {
        return null;
      }
    } catch (e) {
      realDebugPrint('Error when calling assets picker: $e');
      return null;
    }
  }

  /// Register observe callback with assets changes.
  /// 注册资源（图库）变化的监听回调
  static void registerObserve([ValueChanged<MethodCall> callback]) {
    try {
      PhotoManager.addChangeCallback(callback);
      PhotoManager.startChangeNotify();
    } catch (e) {
      realDebugPrint('Error when registering assets callback: $e');
    }
  }

  /// Unregister the observation callback with assets changes.
  /// 取消注册资源（图库）变化的监听回调
  static void unregisterObserve([ValueChanged<MethodCall> callback]) {
    try {
      PhotoManager.removeChangeCallback(callback);
      PhotoManager.stopChangeNotify();
    } catch (e) {
      realDebugPrint('Error when unregistering assets callback: $e');
    }
  }

  /// Build a dark theme according to the theme color.
  /// 通过主题色构建一个默认的暗黑主题
  static ThemeData themeData(Color themeColor) {
    return ThemeData.dark().copyWith(
      buttonColor: themeColor,
      brightness: Brightness.dark,
      primaryColor: Colors.grey[900],
      primaryColorBrightness: Brightness.dark,
      primaryColorLight: Colors.grey[900],
      primaryColorDark: Colors.grey[900],
      accentColor: themeColor,
      accentColorBrightness: Brightness.dark,
      canvasColor: Colors.grey[850],
      scaffoldBackgroundColor: Colors.grey[900],
      bottomAppBarColor: Colors.grey[900],
      cardColor: Colors.grey[900],
      highlightColor: Colors.transparent,
      toggleableActiveColor: themeColor,
      cursorColor: themeColor,
      textSelectionColor: themeColor.withAlpha(100),
      textSelectionHandleColor: themeColor,
      indicatorColor: themeColor,
      appBarTheme: const AppBarTheme(
        brightness: Brightness.dark,
        elevation: 0,
      ),
      colorScheme: ColorScheme(
        primary: Colors.grey[900],
        primaryVariant: Colors.grey[900],
        secondary: themeColor,
        secondaryVariant: themeColor,
        background: Colors.grey[900],
        surface: Colors.grey[900],
        brightness: Brightness.dark,
        error: const Color(0xffcf6679),
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: Colors.white,
        onBackground: Colors.white,
        onError: Colors.black,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return builder.build(context);
  }
}
