import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../constants/constants.dart';
import '../constants/enums.dart';
import '../constants/extensions.dart';
import '../constants/typedefs.dart';
import '../delegates/asset_picker_text_delegate.dart';
import '../internal/singleton.dart';
import '../models/path_wrapper.dart';
import '../provider/asset_picker_provider.dart';
import '../widget/asset_picker.dart';
import '../widget/asset_picker_app_bar.dart';
import '../widget/asset_picker_viewer.dart';
import '../widget/builder/asset_entity_grid_item_builder.dart';
import '../widget/builder/value_listenable_builder_2.dart';
import '../widget/gaps.dart';
import '../widget/platform_progress_indicator.dart';
import '../widget/scale_text.dart';

class MLAssetPickerBuilderDelegate extends AssetPickerBuilderDelegate<AssetEntity, AssetPathEntity> {
  MLAssetPickerBuilderDelegate({
    required this.provider,
    required super.initialPermission,
    super.gridCount,
    super.pickerTheme,
    super.specialItemPosition,
    super.specialItemBuilder,
    super.loadingIndicatorBuilder,
    super.selectPredicate,
    super.shouldRevertGrid,
    super.limitedPermissionOverlayPredicate,
    super.pathNameBuilder,
    super.themeColor,
    super.textDelegate,
    super.locale,
    this.gridThumbnailSize = defaultAssetGridPreviewSize,
    this.previewThumbnailSize,
    this.specialPickerType,
    this.keepScrollOffset = false,
  }) {
// Add the listener if [keepScrollOffset] is true.
    if (keepScrollOffset) {
      gridScrollController.addListener(keepScrollOffsetListener);
    }
  }

  /// [ChangeNotifier] for asset picker.
  /// 资源选择器状态保持
  final DefaultAssetPickerProvider provider;

  /// Thumbnail size in the grid.
  /// 预览时网络的缩略图大小
  ///
  /// This only works on images and videos since other types does not have to
  /// request for the thumbnail data. The preview can speed up by reducing it.
  /// 该参数仅生效于图片和视频类型的资源，因为其他资源不需要请求缩略图数据。
  /// 预览图片的速度可以通过适当降低它的数值来提升。
  ///
  /// This cannot be `null` or a large value since you shouldn't use the
  /// original data for the grid.
  /// 该值不能为空或者非常大，因为在网格中使用原数据不是一个好的决定。
  final ThumbnailSize gridThumbnailSize;

  /// Preview thumbnail size in the viewer.
  /// 预览时图片的缩略图大小
  ///
  /// This only works on images and videos since other types does not have to
  /// request for the thumbnail data. The preview can speed up by reducing it.
  /// 该参数仅生效于图片和视频类型的资源，因为其他资源不需要请求缩略图数据。
  /// 预览图片的速度可以通过适当降低它的数值来提升。
  ///
  /// Default is `null`, which will request the origin data.
  /// 默认为空，即读取原图。
  final ThumbnailSize? previewThumbnailSize;

  /// The current special picker type for the picker.
  /// 当前特殊选择类型
  ///
  /// Several types which are special:
  /// * [SpecialPickerType.wechatMoment] When user selected video, no more images
  /// can be selected.
  /// * [SpecialPickerType.noPreview] Disable preview of asset; Clicking on an
  /// asset selects it.
  ///
  /// 这里包含一些特殊选择类型：
  /// * [SpecialPickerType.wechatMoment] 微信朋友圈模式。当用户选择了视频，将不能选择图片。
  /// * [SpecialPickerType.noPreview] 禁用资源预览。多选时单击资产将直接选中，单选时选中并返回。
  final SpecialPickerType? specialPickerType;

  /// Whether the picker should save the scroll offset between pushes and pops.
  /// 选择器是否可以从同样的位置开始选择
  final bool keepScrollOffset;

  /// [Duration] when triggering path switching.
  /// 切换路径时的动画时长
  Duration get switchingPathDuration => const Duration(milliseconds: 300);

  /// [Curve] when triggering path switching.
  /// 切换路径时的动画曲线
  Curve get switchingPathCurve => Curves.easeInOutQuad;

  /// Whether the [SpecialPickerType.wechatMoment] is enabled.
  /// 当前是否为微信朋友圈选择模式
  bool get isWeChatMoment => specialPickerType == SpecialPickerType.wechatMoment;

  /// Whether the preview of assets is enabled.
  /// 资源的预览是否启用
  bool get isPreviewEnabled => specialPickerType != SpecialPickerType.noPreview;

  @override
  bool get isSingleAssetMode => provider.maxAssets == 1;

  /// The listener to track the scroll position of the [gridScrollController]
  /// if [keepScrollOffset] is true.
  /// 当 [keepScrollOffset] 为 true 时，跟踪 [gridScrollController] 位置的监听。
  void keepScrollOffsetListener() {
    if (gridScrollController.hasClients) {
      Singleton.scrollPosition = gridScrollController.position;
    }
  }

  /// Be aware that the method will do nothing when [keepScrollOffset] is true.
  /// 注意当 [keepScrollOffset] 为 true 时方法不会进行释放。
  @override
  void dispose() {
    // Skip delegate's dispose when it's keeping scroll offset.
    if (keepScrollOffset) {
      return;
    }
    super.dispose();
  }

  @override
  Future<void> selectAsset(
    BuildContext context,
    AssetEntity asset,
    bool selected,
  ) async {
    final bool? selectPredicateResult = await selectPredicate?.call(
      context,
      asset,
      selected,
    );
    if (selectPredicateResult == false) {
      return;
    }
    final DefaultAssetPickerProvider provider = context.read<DefaultAssetPickerProvider>();
    if (selected) {
      provider.unSelectAsset(asset);
      return;
    }
    if (isSingleAssetMode) {
      provider.selectedAssets.clear();
    }
    provider.selectAsset(asset);
    if (isSingleAssetMode && !isPreviewEnabled) {
      Navigator.of(context).maybePop(provider.selectedAssets);
    }
  }

  @override
  Future<void> onAssetsChanged(MethodCall call, StateSetter setState) async {
    if (!isPermissionLimited) {
      return;
    }
    final PathWrapper<AssetPathEntity>? currentWrapper = provider.currentPath;
    if (call.arguments is Map) {
      final Map<dynamic, dynamic> arguments = call.arguments as Map<dynamic, dynamic>;
      if (arguments['newCount'] == 0) {
        provider
          ..currentAssets = <AssetEntity>[]
          ..currentPath = null
          ..hasAssetsToDisplay = false
          ..isAssetsEmpty = true;
        return;
      }
      if (currentWrapper == null) {
        await provider.getPaths();
      }
    }
    if (currentWrapper != null) {
      final AssetPathEntity newPath = await currentWrapper.path.obtainForNewProperties();
      final int assetCount = await newPath.assetCountAsync;
      provider
        ..currentPath = PathWrapper<AssetPathEntity>(path: newPath)
        ..hasAssetsToDisplay = assetCount != 0
        ..isAssetsEmpty = assetCount == 0
        ..totalAssetsCount = assetCount;
      isSwitchingPath.value = false;
      if (newPath.isAll) {
        await provider.getAssetsFromCurrentPath();
      }
    }
  }

  Future<void> _pushAssetToViewer(
    BuildContext context,
    int index,
    AssetEntity asset,
  ) async {
    final DefaultAssetPickerProvider provider = context.read<DefaultAssetPickerProvider>();
    bool selectedAllAndNotSelected() => !provider.selectedAssets.contains(asset) && provider.selectedMaximumAssets;
    bool selectedPhotosAndIsVideo() => isWeChatMoment && asset.type == AssetType.video && provider.selectedAssets.isNotEmpty;
    // When we reached the maximum select count and the asset
    // is not selected, do nothing.
    // When the special type is WeChat Moment, pictures and videos cannot
    // be selected at the same time. Video select should be banned if any
    // pictures are selected.
    if (selectedAllAndNotSelected() || selectedPhotosAndIsVideo()) {
      return;
    }
    final List<AssetEntity> current;
    final List<AssetEntity>? selected;
    final int effectiveIndex;
    if (isWeChatMoment) {
      if (asset.type == AssetType.video) {
        current = <AssetEntity>[asset];
        selected = null;
        effectiveIndex = 0;
      } else {
        current = provider.currentAssets.where((AssetEntity e) => e.type == AssetType.image).toList();
        selected = provider.selectedAssets;
        effectiveIndex = current.indexOf(asset);
      }
    } else {
      current = provider.currentAssets;
      selected = provider.selectedAssets;
      effectiveIndex = index;
    }
    final List<AssetEntity>? result = await AssetPickerViewer.pushToViewer(
      context,
      currentIndex: effectiveIndex,
      previewAssets: current,
      themeData: theme,
      previewThumbnailSize: previewThumbnailSize,
      selectPredicate: selectPredicate,
      selectedAssets: selected,
      selectorProvider: provider,
      specialPickerType: specialPickerType,
      maxAssets: provider.maxAssets,
      shouldReversePreview: isAppleOS,
    );
    if (result != null) {
      Navigator.of(context).maybePop(result);
    }
  }

  @override
  AssetPickerAppBar appBar(BuildContext context) {
    return AssetPickerAppBar(
      backgroundColor: theme.appBarTheme.backgroundColor,
      centerTitle: isAppleOS,
      // title: Semantics(
      //   onTapHint: semanticsTextDelegate.sActionSwitchPathLabel,
      //   child: pathEntitySelector(context),
      // ),
      title: _selectionTitle(),
      leading: backButton(context),
      // Condition for displaying the confirm button:
      // - On Android, show if preview is enabled or if multi asset mode.
      //   If no preview and single asset mode, do not show confirm button,
      //   because any click on an asset selects it.
      // - On iOS, show if no preview and multi asset mode. This is because for iOS
      //   the [bottomActionBar] has the confirm button, but if no preview,
      //   [bottomActionBar] is not displayed.
      // actions: (!isAppleOS || !isPreviewEnabled) && (isPreviewEnabled || !isSingleAssetMode) ? <Widget>[confirmButton(context)] : null,
      actions: (isPreviewEnabled || !isSingleAssetMode) ? <Widget>[confirmButton(context)] : null,
      blurRadius: isAppleOS ? appleOSBlurRadius : 0,
    );
  }

  Widget _selectionTitle() {
    return Consumer<DefaultAssetPickerProvider>(
      builder: (_, DefaultAssetPickerProvider p, __) {
        return ScaleText(
          p.isSelectedNotEmpty && !isSingleAssetMode
              // ? '${textDelegate.confirm}'' (${p.selectedAssets.length}/${p.maxAssets})'
              ? textDelegate.assetSelected.replaceAll('{}', '${p.selectedAssets.length}/${p.maxAssets}')
              : textDelegate.selectionTitle,
          style: TextStyle(
            color: theme.textTheme.bodyText1?.color,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }

  @override
  Widget androidLayout(BuildContext context) {
    return AssetPickerAppBarWrapper(
      appBar: appBar(context),
      body: Consumer<DefaultAssetPickerProvider>(
        builder: (BuildContext context, DefaultAssetPickerProvider p, _) {
          final bool shouldDisplayAssets = p.hasAssetsToDisplay || shouldBuildSpecialItem;
          return AnimatedSwitcher(
            duration: switchingPathDuration,
            child: shouldDisplayAssets
                ? Stack(
                    children: <Widget>[
                      RepaintBoundary(
                        child: Column(
                          children: <Widget>[
                            Expanded(child: assetsGridBuilder(context)),
                            // if (!isSingleAssetMode && isPreviewEnabled) bottomActionBar(context),
                          ],
                        ),
                      ),
                      pathEntityListBackdrop(context),
                      pathEntityListWidget(context),
                    ],
                  )
                : loadingIndicator(context),
          );
        },
      ),
    );
  }

  @override
  Widget appleOSLayout(BuildContext context) {
    // Widget _gridLayout(BuildContext context) {
    //   return ValueListenableBuilder<bool>(
    //     valueListenable: isSwitchingPath,
    //     builder: (_, bool isSwitchingPath, __) => Semantics(
    //       excludeSemantics: isSwitchingPath,
    //       child: RepaintBoundary(
    //         child: Stack(
    //           children: <Widget>[
    //             Positioned.fill(child: assetsGridBuilder(context)),
    //             if ((!isSingleAssetMode || isAppleOS) && isPreviewEnabled)
    //               Positioned.fill(
    //                 top: null,
    //                 child: bottomActionBar(context),
    //               ),
    //           ],
    //         ),
    //       ),
    //     ),
    //   );
    // }
    //
    // Widget _layout(BuildContext context) {
    //   return Stack(
    //     children: <Widget>[
    //       Positioned.fill(
    //         child: Consumer<DefaultAssetPickerProvider>(
    //           builder: (_, DefaultAssetPickerProvider p, __) {
    //             final Widget child;
    //             final bool shouldDisplayAssets = p.hasAssetsToDisplay || shouldBuildSpecialItem;
    //             if (shouldDisplayAssets) {
    //               child = Stack(
    //                 children: <Widget>[
    //                   _gridLayout(context),
    //                   pathEntityListBackdrop(context),
    //                   pathEntityListWidget(context),
    //                 ],
    //               );
    //             } else {
    //               child = loadingIndicator(context);
    //             }
    //             return AnimatedSwitcher(
    //               duration: switchingPathDuration,
    //               child: child,
    //             );
    //           },
    //         ),
    //       ),
    //       appBar(context),
    //     ],
    //   );
    // }
    //
    // return ValueListenableBuilder<bool>(
    //   valueListenable: permissionOverlayDisplay,
    //   builder: (_, bool value, Widget? child) {
    //     if (value) {
    //       return ExcludeSemantics(child: child);
    //     }
    //     return child!;
    //   },
    //   child: _layout(context),
    // );
    return androidLayout(context);
  }

  @override
  Widget assetsGridBuilder(BuildContext context) {
    return Selector<DefaultAssetPickerProvider, PathWrapper<AssetPathEntity>?>(
      selector: (_, DefaultAssetPickerProvider p) => p.currentPath,
      builder: (
        BuildContext context,
        PathWrapper<AssetPathEntity>? wrapper,
        __,
      ) {
        // First, we need the count of the assets.
        int totalCount = wrapper?.assetCount ?? 0;
        final Widget? specialItem;
        // If user chose a special item's position, add 1 count.
        if (specialItemPosition != SpecialItemPosition.none) {
          specialItem = specialItemBuilder?.call(
            context,
            wrapper?.path,
            totalCount,
          );
          if (specialItem != null) {
            totalCount += 1;
          }
        } else {
          specialItem = null;
        }
        if (totalCount == 0 && specialItem == null) {
          return loadingIndicatorBuilder?.call(context, true) ?? loadingIndicator(context);
        }
        // Then we use the [totalCount] to calculate placeholders we need.
        final int placeholderCount;
        if (effectiveShouldRevertGrid && totalCount % gridCount != 0) {
          // When there are left items that not filled into one row,
          // filled the row with placeholders.
          placeholderCount = gridCount - totalCount % gridCount;
        } else {
          // Otherwise, we don't need placeholders.
          placeholderCount = 0;
        }
        // Calculate rows count.
        final int row = (totalCount + placeholderCount) ~/ gridCount;
        // Here we got a magic calculation. [itemSpacing] needs to be divided by
        // [gridCount] since every grid item is squeezed by the [itemSpacing],
        // and it's actual size is reduced with [itemSpacing / gridCount].
        final double dividedSpacing = itemSpacing / gridCount;
        final double topPadding = context.topPadding + kToolbarHeight;

        Widget _sliverGrid(BuildContext context, List<AssetEntity> assets) {
          return SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (_, int index) => Builder(
                builder: (BuildContext context) {
                  if (effectiveShouldRevertGrid) {
                    if (index < placeholderCount) {
                      return const SizedBox.shrink();
                    }
                    index -= placeholderCount;
                  }
                  return MergeSemantics(
                    child: Directionality(
                      textDirection: Directionality.of(context),
                      child: assetGridItemBuilder(
                        context,
                        index,
                        assets,
                        specialItem: specialItem,
                      ),
                    ),
                  );
                },
              ),
              childCount: assetsGridItemCount(
                context: context,
                assets: assets,
                placeholderCount: placeholderCount,
                specialItem: specialItem,
              ),
              findChildIndexCallback: (Key? key) {
                if (key is ValueKey<String>) {
                  return findChildIndexBuilder(
                    id: key.value,
                    assets: assets,
                    placeholderCount: placeholderCount,
                  );
                }
                return null;
              },
              // Explicitly disable semantic indexes for custom usage.
              addSemanticIndexes: false,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridCount,
              mainAxisSpacing: itemSpacing,
              crossAxisSpacing: itemSpacing,
            ),
          );
        }

        return LayoutBuilder(
          builder: (BuildContext c, BoxConstraints constraints) {
            final double itemSize = constraints.maxWidth / gridCount;
            // Check whether all rows can be placed at the same time.
            final bool onlyOneScreen = row * itemSize <= constraints.maxHeight - context.bottomPadding - topPadding - permissionLimitedBarHeight;
            final double height;
            if (onlyOneScreen) {
              height = constraints.maxHeight;
            } else {
              // Reduce [permissionLimitedBarHeight] for the final height.
              height = constraints.maxHeight - permissionLimitedBarHeight;
            }
            // Use [ScrollView.anchor] to determine where is the first place of
            // the [SliverGrid]. Each row needs [dividedSpacing] to calculate,
            // then minus one times of [itemSpacing] because spacing's count in the
            // cross axis is always less than the rows.
            final double anchor = math.min(
              (row * (itemSize + dividedSpacing) + topPadding - itemSpacing) / height,
              1,
            );

            return Directionality(
              textDirection: effectiveGridDirection(context),
              child: ColoredBox(
                color: theme.canvasColor,
                child: Selector<DefaultAssetPickerProvider, List<AssetEntity>>(
                  selector: (_, DefaultAssetPickerProvider p) => p.currentAssets,
                  builder: (_, List<AssetEntity> assets, __) {
                    final SliverGap bottomGap = SliverGap.v(
                      context.bottomPadding + bottomSectionHeight,
                    );
                    return CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: gridScrollController,
                      anchor: effectiveShouldRevertGrid ? anchor : 0,
                      center: effectiveShouldRevertGrid ? gridRevertKey : null,
                      slivers: <Widget>[
                        if (isAppleOS) SliverGap.v(context.topPadding + kToolbarHeight),
                        _sliverGrid(_, assets),
                        // Ignore the gap when the [anchor] is not equal to 1.
                        if (effectiveShouldRevertGrid && anchor == 1) bottomGap,
                        if (effectiveShouldRevertGrid)
                          SliverToBoxAdapter(
                            key: gridRevertKey,
                            child: const SizedBox.shrink(),
                          ),
                        if (isAppleOS && !effectiveShouldRevertGrid) bottomGap,
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// There are several conditions within this builder:
  ///  * Return item builder according to the asset's type.
  ///    * [AssetType.audio] -> [audioItemBuilder]
  ///    * [AssetType.image], [AssetType.video] -> [imageAndVideoItemBuilder]
  ///  * Load more assets when the index reached at third line counting
  ///    backwards.
  ///
  /// 资源构建有几个条件：
  ///  * 根据资源类型返回对应类型的构建：
  ///    * [AssetType.audio] -> [audioItemBuilder] 音频类型
  ///    * [AssetType.image], [AssetType.video] -> [imageAndVideoItemBuilder]
  ///      图片和视频类型
  ///  * 在索引到达倒数第三列的时候加载更多资源。
  @override
  Widget assetGridItemBuilder(
    BuildContext context,
    int index,
    List<AssetEntity> currentAssets, {
    Widget? specialItem,
  }) {
    final int length = currentAssets.length;
    final PathWrapper<AssetPathEntity>? currentWrapper = context.select<DefaultAssetPickerProvider, PathWrapper<AssetPathEntity>?>(
      (DefaultAssetPickerProvider p) => p.currentPath,
    );
    final AssetPathEntity? currentPathEntity = currentWrapper?.path;

    if (specialItem != null) {
      if ((index == 0 && specialItemPosition == SpecialItemPosition.prepend) || (index == length && specialItemPosition == SpecialItemPosition.append)) {
        return specialItem;
      }
    }

    final int currentIndex;
    if (specialItem != null && specialItemPosition == SpecialItemPosition.prepend) {
      currentIndex = index - 1;
    } else {
      currentIndex = index;
    }

    if (currentPathEntity == null) {
      return const SizedBox.shrink();
    }

    final bool hasMoreToLoad = context.select<DefaultAssetPickerProvider, bool>(
      (DefaultAssetPickerProvider p) => p.hasMoreToLoad,
    );
    if (index == length - gridCount * 3 && hasMoreToLoad) {
      context.read<DefaultAssetPickerProvider>().loadMoreAssets();
    }

    final AssetEntity asset = currentAssets.elementAt(currentIndex);
    final Widget builder;
    switch (asset.type) {
      case AssetType.audio:
        builder = audioItemBuilder(context, currentIndex, asset);
        break;
      case AssetType.image:
      case AssetType.video:
        builder = imageAndVideoItemBuilder(context, currentIndex, asset);
        break;
      case AssetType.other:
        builder = const SizedBox.shrink();
        break;
    }
    final Widget content = Stack(
      key: ValueKey<String>(asset.id),
      children: <Widget>[
        builder,
        selectedBackdrop(context, currentIndex, asset),
        if (!isWeChatMoment || asset.type != AssetType.video) selectIndicator(context, index, asset),
        itemBannedIndicator(context, asset),
      ],
    );
    return assetGridItemSemanticsBuilder(context, index, asset, content);
  }

  int semanticIndex(int index) {
    if (specialItemPosition != SpecialItemPosition.prepend) {
      return index + 1;
    }
    return index;
  }

  @override
  Widget assetGridItemSemanticsBuilder(
    BuildContext context,
    int index,
    AssetEntity asset,
    Widget child,
  ) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSwitchingPath,
      builder: (_, bool isSwitchingPath, Widget? child) {
        return Consumer<DefaultAssetPickerProvider>(
          builder: (_, DefaultAssetPickerProvider p, __) {
            final bool isBanned = (!p.selectedAssets.contains(asset) && p.selectedMaximumAssets) || (isWeChatMoment && asset.type == AssetType.video && p.selectedAssets.isNotEmpty);
            final bool isSelected = p.selectedDescriptions.contains(
              asset.toString(),
            );
            final int selectedIndex = p.selectedAssets.indexOf(asset) + 1;
            String hint = '';
            if (asset.type == AssetType.audio || asset.type == AssetType.video) {
              hint += '${semanticsTextDelegate.sNameDurationLabel}: ';
              hint += semanticsTextDelegate.durationIndicatorBuilder(
                asset.videoDuration,
              );
            }
            if (asset.title?.isNotEmpty ?? false) {
              hint += ', ${asset.title}';
            }
            return Semantics(
              button: false,
              enabled: !isBanned,
              excludeSemantics: true,
              focusable: !isSwitchingPath,
              label: '${semanticsTextDelegate.semanticTypeLabel(asset.type)}'
                  '${semanticIndex(index)}, '
                  '${asset.createDateTime.toString().replaceAll('.000', '')}',
              hidden: isSwitchingPath,
              hint: hint,
              image: asset.type == AssetType.image || asset.type == AssetType.video,
              onTap: () => selectAsset(context, asset, isSelected),
              onTapHint: semanticsTextDelegate.sActionSelectHint,
              onLongPress: isPreviewEnabled ? () => _pushAssetToViewer(context, index, asset) : null,
              onLongPressHint: semanticsTextDelegate.sActionPreviewHint,
              selected: isSelected,
              sortKey: OrdinalSortKey(
                semanticIndex(index).toDouble(),
                name: 'GridItem',
              ),
              value: selectedIndex > 0 ? '$selectedIndex' : null,
              child: GestureDetector(
                // Regression https://github.com/flutter/flutter/issues/35112.
                onLongPress: isPreviewEnabled && context.mediaQuery.accessibleNavigation ? () => _pushAssetToViewer(context, index, asset) : null,
                child: IndexedSemantics(
                  index: semanticIndex(index),
                  child: child,
                ),
              ),
            );
          },
        );
      },
      child: child,
    );
  }

  @override
  int findChildIndexBuilder({
    required String id,
    required List<AssetEntity> assets,
    int placeholderCount = 0,
  }) {
    int index = assets.indexWhere((AssetEntity e) => e.id == id);
    if (specialItemPosition == SpecialItemPosition.prepend) {
      index += 1;
    }
    index += placeholderCount;
    return index;
  }

  @override
  int assetsGridItemCount({
    required BuildContext context,
    required List<AssetEntity> assets,
    int placeholderCount = 0,
    Widget? specialItem,
  }) {
    final PathWrapper<AssetPathEntity>? currentWrapper = context.select<DefaultAssetPickerProvider, PathWrapper<AssetPathEntity>?>(
      (DefaultAssetPickerProvider p) => p.currentPath,
    );
    final AssetPathEntity? currentPathEntity = currentWrapper?.path;
    final int length = assets.length + placeholderCount;

    // Return 1 if the [specialItem] build something.
    if (currentPathEntity == null && specialItem != null) {
      return placeholderCount + 1;
    }

    // Return actual length if the current path is all.
    // 如果当前目录是全部内容，则返回实际的内容数量。
    if (currentPathEntity?.isAll != true) {
      return length;
    }
    switch (specialItemPosition) {
      case SpecialItemPosition.none:
        return length;
      case SpecialItemPosition.prepend:
      case SpecialItemPosition.append:
        return length + 1;
    }
  }

  @override
  Widget audioIndicator(BuildContext context, AssetEntity asset) {
    return Container(
      width: double.maxFinite,
      alignment: AlignmentDirectional.bottomStart,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.bottomCenter,
          end: AlignmentDirectional.topCenter,
          colors: <Color>[theme.dividerColor, Colors.transparent],
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: ScaleText(
          textDelegate.durationIndicatorBuilder(
            Duration(seconds: asset.duration),
          ),
          style: const TextStyle(fontSize: 16),
          semanticsLabel: '${semanticsTextDelegate.sNameDurationLabel}: '
              '${semanticsTextDelegate.durationIndicatorBuilder(
            Duration(seconds: asset.duration),
          )}',
        ),
      ),
    );
  }

  @override
  Widget audioItemBuilder(BuildContext context, int index, AssetEntity asset) {
    return Stack(
      children: <Widget>[
        Container(
          width: double.maxFinite,
          alignment: AlignmentDirectional.topStart,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topCenter,
              end: AlignmentDirectional.bottomCenter,
              colors: <Color>[theme.dividerColor, Colors.transparent],
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 30),
            child: ScaleText(
              asset.title ?? '',
              style: const TextStyle(fontSize: 16),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const Align(
          alignment: AlignmentDirectional(0.9, 0.8),
          child: Icon(Icons.audiotrack),
        ),
        audioIndicator(context, asset),
      ],
    );
  }

  /// It'll pop with [AssetPickerProvider.selectedAssets]
  /// when there are any assets were chosen.
  /// 当有资源已选时，点击按钮将把已选资源通过路由返回。
  @override
  Widget confirmButton(BuildContext context) {
    return Consumer<DefaultAssetPickerProvider>(
      builder: (_, DefaultAssetPickerProvider p, __) {
        return Consumer<DefaultAssetPickerProvider>(
          builder: (_, DefaultAssetPickerProvider p, __) {
            return TextButton(onPressed: () =>  Navigator.of(context).maybePop(p.selectedAssets),
              child: Text(
                textDelegate.done,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
              ),);
          },
        );
      },
    );
  }

  @override
  Widget imageAndVideoItemBuilder(
    BuildContext context,
    int index,
    AssetEntity asset,
  ) {
    final AssetEntityImageProvider imageProvider = AssetEntityImageProvider(
      asset,
      isOriginal: false,
      thumbnailSize: gridThumbnailSize,
    );
    SpecialImageType? type;
    if (imageProvider.imageFileType == ImageFileType.gif) {
      type = SpecialImageType.gif;
    } else if (imageProvider.imageFileType == ImageFileType.heic) {
      type = SpecialImageType.heic;
    }
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: AssetEntityGridItemBuilder(
              image: imageProvider,
              failedItemBuilder: failedItemBuilder,
            ),
          ),
        ),
        if (type == SpecialImageType.gif) // 如果为GIF则显示标识
          gifIndicator(context, asset),
        if (asset.type == AssetType.video) // 如果为视频则显示标识
          videoIndicator(context, asset),
      ],
    );
  }

  @override
  Widget loadingIndicator(BuildContext context) {
    return Center(
      child: Selector<DefaultAssetPickerProvider, bool>(
        selector: (_, DefaultAssetPickerProvider p) => p.isAssetsEmpty,
        builder: (BuildContext context, bool isAssetsEmpty, __) {
          if (isAssetsEmpty) {
            return emptyIndicator(context);
          }
          return PlatformProgressIndicator(
            color: theme.iconTheme.color,
            size: context.mediaQuery.size.width / gridCount / 3,
          );
        },
      ),
    );
  }

  /// While the picker is switching path, this will displayed.
  /// If the user tapped on it, it'll collapse the list widget.
  ///
  /// 当选择器正在选择路径时，它会出现。用户点击它时，列表会折叠收起。
  @override
  Widget pathEntityListBackdrop(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSwitchingPath,
      builder: (_, bool isSwitchingPath, __) => Positioned.fill(
        child: IgnorePointer(
          ignoring: !isSwitchingPath,
          ignoringSemantics: true,
          child: GestureDetector(
            onTap: () => this.isSwitchingPath.value = false,
            child: AnimatedOpacity(
              duration: switchingPathDuration,
              opacity: isSwitchingPath ? .75 : 0,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget pathEntityListWidget(BuildContext context) {
    return Positioned.fill(
      top: isAppleOS ? context.topPadding + kToolbarHeight : 0,
      bottom: null,
      child: ValueListenableBuilder<bool>(
        valueListenable: isSwitchingPath,
        builder: (_, bool isSwitchingPath, Widget? child) => Semantics(
          hidden: isSwitchingPath ? null : true,
          child: AnimatedAlign(
            duration: switchingPathDuration,
            curve: switchingPathCurve,
            alignment: Alignment.bottomCenter,
            heightFactor: isSwitchingPath ? 1 : 0,
            child: AnimatedOpacity(
              duration: switchingPathDuration,
              curve: switchingPathCurve,
              opacity: !isAppleOS || isSwitchingPath ? 1 : 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(10),
                ),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: context.mediaQuery.size.height * (isAppleOS ? .6 : .8),
                  ),
                  color: theme.colorScheme.background,
                  child: child,
                ),
              ),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ValueListenableBuilder<PermissionState>(
              valueListenable: permission,
              builder: (_, PermissionState ps, Widget? child) => Semantics(
                label: '${semanticsTextDelegate.viewingLimitedAssetsTip}, '
                    '${semanticsTextDelegate.changeAccessibleLimitedAssets}',
                button: true,
                onTap: PhotoManager.presentLimited,
                hidden: !isPermissionLimited,
                focusable: isPermissionLimited,
                excludeSemantics: true,
                child: isPermissionLimited ? child : const SizedBox.shrink(),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Text.rich(
                  TextSpan(
                    children: <TextSpan>[
                      TextSpan(
                        text: textDelegate.viewingLimitedAssetsTip,
                      ),
                      TextSpan(
                        text: ' '
                            '${textDelegate.changeAccessibleLimitedAssets}',
                        style: TextStyle(color: interactiveTextColor(context)),
                        recognizer: TapGestureRecognizer()..onTap = PhotoManager.presentLimited,
                      ),
                    ],
                  ),
                  style: context.themeData.textTheme.caption?.copyWith(
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            Flexible(
              child: Selector<DefaultAssetPickerProvider, List<PathWrapper<AssetPathEntity>>>(
                selector: (_, DefaultAssetPickerProvider p) => p.paths,
                builder: (_, List<PathWrapper<AssetPathEntity>> paths, __) {
                  final List<PathWrapper<AssetPathEntity>> filtered = paths
                      .where(
                        (PathWrapper<AssetPathEntity> p) => p.assetCount != 0,
                      )
                      .toList();
                  return ListView.separated(
                    padding: const EdgeInsetsDirectional.only(top: 1),
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (BuildContext c, int i) => pathEntityWidget(
                      context: c,
                      list: filtered,
                      index: i,
                    ),
                    separatorBuilder: (_, __) => Container(
                      margin: const EdgeInsetsDirectional.only(start: 60),
                      height: 1,
                      color: theme.canvasColor,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget pathEntitySelector(BuildContext context) {
    Widget _text(
      BuildContext context,
      String text,
      String semanticsText,
    ) {
      return Flexible(
        child: ScaleText(
          text,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.fade,
          maxScaleFactor: 1.2,
          semanticsLabel: semanticsText,
        ),
      );
    }

    return UnconstrainedBox(
      child: GestureDetector(
        onTap: () {
          if (provider.currentPath == null) {
            return;
          }
          Feedback.forTap(context);
          if (isPermissionLimited && provider.isAssetsEmpty) {
            PhotoManager.presentLimited();
            return;
          }
          isSwitchingPath.value = !isSwitchingPath.value;
        },
        child: Container(
          height: appBarItemHeight,
          constraints: BoxConstraints(
            maxWidth: context.mediaQuery.size.width * 0.5,
          ),
          padding: const EdgeInsetsDirectional.only(start: 12, end: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: theme.dividerColor,
          ),
          child: Selector<DefaultAssetPickerProvider, PathWrapper<AssetPathEntity>?>(
            selector: (_, DefaultAssetPickerProvider p) => p.currentPath,
            builder: (_, PathWrapper<AssetPathEntity>? p, Widget? w) {
              final AssetPathEntity? path = p?.path;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (path == null && isPermissionLimited)
                    _text(
                      context,
                      textDelegate.changeAccessibleLimitedAssets,
                      semanticsTextDelegate.changeAccessibleLimitedAssets,
                    ),
                  if (path != null)
                    _text(
                      context,
                      isPermissionLimited && path.isAll ? textDelegate.accessiblePathName : pathNameBuilder?.call(path) ?? path.name,
                      isPermissionLimited && path.isAll ? semanticsTextDelegate.accessiblePathName : pathNameBuilder?.call(path) ?? path.name,
                    ),
                  w!,
                ],
              );
            },
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.iconTheme.color!.withOpacity(0.5),
                ),
                child: ValueListenableBuilder<bool>(
                  valueListenable: isSwitchingPath,
                  builder: (_, bool isSwitchingPath, Widget? w) {
                    return Transform.rotate(
                      angle: isSwitchingPath ? math.pi : 0,
                      child: w,
                    );
                  },
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget pathEntityWidget({
    required BuildContext context,
    required List<PathWrapper<AssetPathEntity>> list,
    required int index,
  }) {
    final PathWrapper<AssetPathEntity> wrapper = list[index];
    final AssetPathEntity pathEntity = wrapper.path;
    final Uint8List? data = wrapper.thumbnailData;

    Widget builder() {
      if (data != null) {
        return Image.memory(data, fit: BoxFit.cover);
      }
      if (pathEntity.type.containsAudio()) {
        return ColoredBox(
          color: theme.colorScheme.primary.withOpacity(0.12),
          child: const Center(child: Icon(Icons.audiotrack)),
        );
      }
      return ColoredBox(color: theme.colorScheme.primary.withOpacity(0.12));
    }

    final String pathName = pathNameBuilder?.call(pathEntity) ?? pathEntity.name;
    final String name = isPermissionLimited && pathEntity.isAll ? textDelegate.accessiblePathName : pathName;
    final String semanticsName = isPermissionLimited && pathEntity.isAll ? semanticsTextDelegate.accessiblePathName : pathName;
    final String? semanticsCount = wrapper.assetCount?.toString();
    final StringBuffer labelBuffer = StringBuffer(
      '$semanticsName, ${semanticsTextDelegate.sUnitAssetCountLabel}',
    );
    if (semanticsCount != null) {
      labelBuffer.write(': $semanticsCount');
    }
    return Selector<DefaultAssetPickerProvider, PathWrapper<AssetPathEntity>?>(
      selector: (_, DefaultAssetPickerProvider p) => p.currentPath,
      builder: (_, PathWrapper<AssetPathEntity>? currentWrapper, __) {
        final bool isSelected = currentWrapper?.path == pathEntity;
        return Semantics(
          label: labelBuffer.toString(),
          selected: isSelected,
          onTapHint: semanticsTextDelegate.sActionSwitchPathLabel,
          button: false,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              splashFactory: InkSplash.splashFactory,
              onTap: () {
                Feedback.forTap(context);
                context.read<DefaultAssetPickerProvider>().switchPath(wrapper);
                isSwitchingPath.value = false;
                gridScrollController.jumpTo(0);
              },
              child: SizedBox(
                height: isAppleOS ? 64 : 52,
                child: Row(
                  children: <Widget>[
                    RepaintBoundary(
                      child: AspectRatio(aspectRatio: 1, child: builder()),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 15,
                          end: 20,
                        ),
                        child: ExcludeSemantics(
                          child: Row(
                            children: <Widget>[
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 10,
                                  ),
                                  child: ScaleText(
                                    name,
                                    style: const TextStyle(fontSize: 17),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              if (semanticsCount != null)
                                ScaleText(
                                  '($semanticsCount)',
                                  style: TextStyle(
                                    color: theme.textTheme.caption?.color,
                                    fontSize: 17,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (isSelected)
                      AspectRatio(
                        aspectRatio: 1,
                        child: Icon(Icons.check, color: themeColor, size: 26),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget previewButton(BuildContext context) {
    Future<void> _onTap() async {
      final DefaultAssetPickerProvider p = context.read<DefaultAssetPickerProvider>();
      final List<AssetEntity> selectedAssets = p.selectedAssets;
      final List<AssetEntity> selected;
      if (isWeChatMoment) {
        selected = selectedAssets.where((AssetEntity e) => e.type == AssetType.image).toList();
      } else {
        selected = selectedAssets;
      }
      final List<AssetEntity>? result = await AssetPickerViewer.pushToViewer(
        context,
        previewAssets: selected,
        previewThumbnailSize: previewThumbnailSize,
        selectPredicate: selectPredicate,
        selectedAssets: selected,
        selectorProvider: provider,
        themeData: theme,
        maxAssets: p.maxAssets,
      );
      if (result != null) {
        Navigator.of(context).maybePop(result);
      }
    }

    return Consumer<DefaultAssetPickerProvider>(
      builder: (_, DefaultAssetPickerProvider p, Widget? child) {
        return ValueListenableBuilder<bool>(
          valueListenable: isSwitchingPath,
          builder: (_, bool isSwitchingPath, __) => Semantics(
            enabled: p.isSelectedNotEmpty,
            focusable: !isSwitchingPath,
            hidden: isSwitchingPath,
            onTapHint: semanticsTextDelegate.sActionPreviewHint,
            child: child,
          ),
        );
      },
      child: Consumer<DefaultAssetPickerProvider>(
        builder: (_, DefaultAssetPickerProvider p, __) => GestureDetector(
          onTap: p.isSelectedNotEmpty ? _onTap : null,
          child: Selector<DefaultAssetPickerProvider, String>(
            selector: (_, DefaultAssetPickerProvider p) => p.selectedDescriptions,
            builder: (BuildContext c, __, ___) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ScaleText(
                '${textDelegate.preview}'
                '${p.isSelectedNotEmpty ? ' (${p.selectedAssets.length})' : ''}',
                style: TextStyle(
                  color: p.isSelectedNotEmpty ? null : c.themeData.textTheme.caption?.color,
                  fontSize: 17,
                ),
                maxScaleFactor: 1.2,
                semanticsLabel: '${semanticsTextDelegate.preview}'
                    '${p.isSelectedNotEmpty ? ' (${p.selectedAssets.length})' : ''}',
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget itemBannedIndicator(BuildContext context, AssetEntity asset) {
    return Consumer<DefaultAssetPickerProvider>(
      builder: (_, DefaultAssetPickerProvider p, __) {
        final bool isDisabled = (!p.selectedAssets.contains(asset) && p.selectedMaximumAssets) || (isWeChatMoment && asset.type == AssetType.video && p.selectedAssets.isNotEmpty);
        if (isDisabled) {
          return Container(
            color: theme.colorScheme.background.withOpacity(.85),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  @override
  Widget selectIndicator(
    BuildContext context,
    int index,
    AssetEntity asset,
  ) {
    final double indicatorSize = context.mediaQuery.size.width / gridCount / 3;
    final Duration duration = switchingPathDuration;
    return Selector<DefaultAssetPickerProvider, String>(
      selector: (_, DefaultAssetPickerProvider p) => p.selectedDescriptions,
      builder: (BuildContext context, String descriptions, __) {
        final bool selected = descriptions.contains(asset.toString());
        final Widget innerSelector = AnimatedContainer(
          duration: duration,
          width: indicatorSize / (isAppleOS ? 1.25 : 1.5),
          height: indicatorSize / (isAppleOS ? 1.25 : 1.5),
          padding: EdgeInsets.all(indicatorSize / 10),
          decoration: BoxDecoration(
            border: !selected
                ? Border.all(
                    color: context.themeData.selectedRowColor,
                    width: indicatorSize / 25,
                  )
                : null,
            color: selected ? themeColor : null,
            shape: BoxShape.circle,
          ),
          child: selected
              ? Consumer<DefaultAssetPickerProvider>(
                  builder: (_, DefaultAssetPickerProvider p, __) {
                    final int index = p.selectedAssets.indexOf(asset);
                    final bool selected = index != -1;
                    return AnimatedSwitcher(
                      duration: duration,
                      reverseDuration: duration,
                      child: selected && !isSingleAssetMode
                          ? Align(
                              alignment: AlignmentDirectional.center,
                              child: SizedBox(
                                height: indicatorSize,
                                child: FittedBox(
                                  alignment: AlignmentDirectional.topStart,
                                  fit: BoxFit.cover,
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: theme.colorScheme.background,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                )
              : const SizedBox.shrink(),
        );
        final Widget selectorWidget = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => selectAsset(context, asset, selected),
          child: Container(
            margin: EdgeInsets.all(indicatorSize / 4),
            width: isPreviewEnabled ? indicatorSize : null,
            height: isPreviewEnabled ? indicatorSize : null,
            alignment: AlignmentDirectional.topEnd,
            child: (!isPreviewEnabled && isSingleAssetMode && !selected) ? const SizedBox.shrink() : innerSelector,
          ),
        );
        if (isPreviewEnabled) {
          return PositionedDirectional(
            top: 0,
            end: 0,
            child: selectorWidget,
          );
        }
        return selectorWidget;
      },
    );
  }

  @override
  Widget selectedBackdrop(BuildContext context, int index, AssetEntity asset) {
    final double indicatorSize = context.mediaQuery.size.width / gridCount / 3;
    return Positioned.fill(
      child: GestureDetector(
        onTap: isPreviewEnabled ? () => _pushAssetToViewer(context, index, asset) : null,
        child: Consumer<DefaultAssetPickerProvider>(
          builder: (_, DefaultAssetPickerProvider p, __) {
            final int index = p.selectedAssets.indexOf(asset);
            final bool selected = index != -1;
            return AnimatedContainer(
              duration: switchingPathDuration,
              padding: EdgeInsets.all(indicatorSize * .35),
              // color: selected ? theme.colorScheme.primary.withOpacity(.45) : theme.backgroundColor.withOpacity(.1),
              color: Colors.transparent,
              child:
                  // selected && !isSingleAssetMode
                  //     ? Align(
                  //         alignment: AlignmentDirectional.topStart,
                  //         child: SizedBox(
                  //           height: indicatorSize / 2.5,
                  //           child: FittedBox(
                  //             alignment: AlignmentDirectional.topStart,
                  //             fit: BoxFit.cover,
                  //             child: Text(
                  //               '${index + 1}',
                  //               style: TextStyle(
                  //                 color: theme.textTheme.bodyText1?.color?.withOpacity(.75),
                  //                 fontWeight: FontWeight.w600,
                  //                 height: 1,
                  //               ),
                  //             ),
                  //           ),
                  //         ),
                  //       )
                  //     :
                  const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
    // return const SizedBox.shrink();
  }

  /// Videos often contains various of color in the cover,
  /// so in order to keep the content visible in most cases,
  /// the color of the indicator has been set to [Colors.white].
  ///
  /// 视频封面通常包含各种颜色，为了保证内容在一般情况下可见，此处
  /// 将指示器的图标和文字设置为 [Colors.white]。
  @override
  Widget videoIndicator(BuildContext context, AssetEntity asset) {
    return PositionedDirectional(
      start: 0,
      end: 0,
      bottom: 0,
      child: Container(
        width: double.maxFinite,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            end: Alignment.topCenter,
            begin: Alignment.bottomCenter,
            // stops: [0.82, 1.0],
            colors: <Color>[
              const Color(0xFF343434),
              Colors.white.withOpacity(0.0),
            ],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: ScaleText(
              textDelegate.durationIndicatorBuilder(
                Duration(seconds: asset.duration),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
              strutStyle: const StrutStyle(
                forceStrutHeight: true,
                height: 1.4,
              ),
              maxLines: 1,
              maxScaleFactor: 1.2,
              semanticsLabel: semanticsTextDelegate.durationIndicatorBuilder(
                Duration(seconds: asset.duration),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Schedule the scroll position's restoration callback if this feature
    // is enabled and offsets are different.
    if (keepScrollOffset && Singleton.scrollPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Update only if the controller has clients.
        if (gridScrollController.hasClients) {
          gridScrollController.jumpTo(Singleton.scrollPosition!.pixels);
        }
      });
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Theme(
        data: theme,
        child: CNP<DefaultAssetPickerProvider>.value(
          value: provider,
          builder: (BuildContext context, _) => Material(
            color: theme.canvasColor,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (isAppleOS) appleOSLayout(context) else androidLayout(context),
                if (Platform.isIOS) iOSPermissionOverlay(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
