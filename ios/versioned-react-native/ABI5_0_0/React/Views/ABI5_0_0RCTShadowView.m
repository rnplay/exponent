/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "ABI5_0_0RCTShadowView.h"

#import "ABI5_0_0RCTConvert.h"
#import "ABI5_0_0RCTLog.h"
#import "ABI5_0_0RCTUtils.h"
#import "UIView+ReactABI5_0_0.h"

typedef void (^ABI5_0_0RCTActionBlock)(ABI5_0_0RCTShadowView *shadowViewSelf, id value);
typedef void (^ABI5_0_0RCTResetActionBlock)(ABI5_0_0RCTShadowView *shadowViewSelf);

static NSString *const ABI5_0_0RCTBackgroundColorProp = @"backgroundColor";

typedef NS_ENUM(unsigned int, meta_prop_t) {
  META_PROP_LEFT,
  META_PROP_TOP,
  META_PROP_RIGHT,
  META_PROP_BOTTOM,
  META_PROP_HORIZONTAL,
  META_PROP_VERTICAL,
  META_PROP_ALL,
  META_PROP_COUNT,
};

@implementation ABI5_0_0RCTShadowView
{
  ABI5_0_0RCTUpdateLifecycle _propagationLifecycle;
  ABI5_0_0RCTUpdateLifecycle _textLifecycle;
  NSDictionary *_lastParentProperties;
  NSMutableArray<ABI5_0_0RCTShadowView *> *_ReactABI5_0_0Subviews;
  BOOL _recomputePadding;
  BOOL _recomputeMargin;
  BOOL _recomputeBorder;
  float _paddingMetaProps[META_PROP_COUNT];
  float _marginMetaProps[META_PROP_COUNT];
  float _borderMetaProps[META_PROP_COUNT];
}

@synthesize ReactABI5_0_0Tag = _ReactABI5_0_0Tag;

// css_node api

static void ABI5_0_0RCTPrint(void *context)
{
  ABI5_0_0RCTShadowView *shadowView = (__bridge ABI5_0_0RCTShadowView *)context;
  printf("%s(%zd), ", shadowView.viewName.UTF8String, shadowView.ReactABI5_0_0Tag.integerValue);
}

static css_node_t *ABI5_0_0RCTGetChild(void *context, int i)
{
  ABI5_0_0RCTShadowView *shadowView = (__bridge ABI5_0_0RCTShadowView *)context;
  ABI5_0_0RCTShadowView *child = [shadowView ReactABI5_0_0Subviews][i];
  return child->_cssNode;
}

static bool ABI5_0_0RCTIsDirty(void *context)
{
  ABI5_0_0RCTShadowView *shadowView = (__bridge ABI5_0_0RCTShadowView *)context;
  return [shadowView isLayoutDirty];
}

// Enforces precedence rules, e.g. marginLeft > marginHorizontal > margin.
static void ABI5_0_0RCTProcessMetaProps(const float metaProps[META_PROP_COUNT], float style[CSS_POSITION_COUNT]) {
  style[CSS_LEFT] = !ABI5_0_0CSSisUndefined(metaProps[META_PROP_LEFT]) ? metaProps[META_PROP_LEFT]
  : !ABI5_0_0CSSisUndefined(metaProps[META_PROP_HORIZONTAL]) ? metaProps[META_PROP_HORIZONTAL]
  : !ABI5_0_0CSSisUndefined(metaProps[META_PROP_ALL]) ? metaProps[META_PROP_ALL]
  : 0;
  style[CSS_RIGHT] = !ABI5_0_0CSSisUndefined(metaProps[META_PROP_RIGHT]) ? metaProps[META_PROP_RIGHT]
  : !ABI5_0_0CSSisUndefined(metaProps[META_PROP_HORIZONTAL]) ? metaProps[META_PROP_HORIZONTAL]
  : !ABI5_0_0CSSisUndefined(metaProps[META_PROP_ALL]) ? metaProps[META_PROP_ALL]
  : 0;
  style[CSS_TOP] = !ABI5_0_0CSSisUndefined(metaProps[META_PROP_TOP]) ? metaProps[META_PROP_TOP]
  : !ABI5_0_0CSSisUndefined(metaProps[META_PROP_VERTICAL]) ? metaProps[META_PROP_VERTICAL]
  : !ABI5_0_0CSSisUndefined(metaProps[META_PROP_ALL]) ? metaProps[META_PROP_ALL]
  : 0;
  style[CSS_BOTTOM] = !ABI5_0_0CSSisUndefined(metaProps[META_PROP_BOTTOM]) ? metaProps[META_PROP_BOTTOM]
  : !ABI5_0_0CSSisUndefined(metaProps[META_PROP_VERTICAL]) ? metaProps[META_PROP_VERTICAL]
  : !ABI5_0_0CSSisUndefined(metaProps[META_PROP_ALL]) ? metaProps[META_PROP_ALL]
  : 0;
}

- (void)fillCSSNode:(css_node_t *)node
{
  node->children_count = (int)_ReactABI5_0_0Subviews.count;
}

// The absolute stuff is so that we can take into account our absolute position when rounding in order to
// snap to the pixel grid. For example, say you have the following structure:
//
// +--------+---------+--------+
// |        |+-------+|        |
// |        ||       ||        |
// |        |+-------+|        |
// +--------+---------+--------+
//
// Say the screen width is 320 pts so the three big views will get the following x bounds from our layout system:
// {0, 106.667}, {106.667, 213.333}, {213.333, 320}
//
// Assuming screen scale is 2, these numbers must be rounded to the nearest 0.5 to fit the pixel grid:
// {0, 106.5}, {106.5, 213.5}, {213.5, 320}
// You'll notice that the three widths are 106.5, 107, 106.5.
//
// This is great for the parent views but it gets trickier when we consider rounding for the subview.
//
// When we go to round the bounds for the subview in the middle, it's relative bounds are {0, 106.667}
// which gets rounded to {0, 106.5}. This will cause the subview to be one pixel smaller than it should be.
// this is why we need to pass in the absolute position in order to do the rounding relative to the screen's
// grid rather than the view's grid.
//
// After passing in the absolutePosition of {106.667, y}, we do the following calculations:
// absoluteLeft = round(absolutePosition.x + viewPosition.left) = round(106.667 + 0) = 106.5
// absoluteRight = round(absolutePosition.x + viewPosition.left + viewSize.left) + round(106.667 + 0 + 106.667) = 213.5
// width = 213.5 - 106.5 = 107
// You'll notice that this is the same width we calculated for the parent view because we've taken its position into account.

- (void)applyLayoutNode:(css_node_t *)node
      viewsWithNewFrame:(NSMutableSet<ABI5_0_0RCTShadowView *> *)viewsWithNewFrame
       absolutePosition:(CGPoint)absolutePosition
{
  if (!node->layout.should_update) {
    return;
  }
  node->layout.should_update = false;
  _layoutLifecycle = ABI5_0_0RCTUpdateLifecycleComputed;

  CGPoint absoluteTopLeft = {
    absolutePosition.x + node->layout.position[CSS_LEFT],
    absolutePosition.y + node->layout.position[CSS_TOP]
  };

  CGPoint absoluteBottomRight = {
    absolutePosition.x + node->layout.position[CSS_LEFT] + node->layout.dimensions[CSS_WIDTH],
    absolutePosition.y + node->layout.position[CSS_TOP] + node->layout.dimensions[CSS_HEIGHT]
  };

  CGRect frame = {{
    ABI5_0_0RCTRoundPixelValue(node->layout.position[CSS_LEFT]),
    ABI5_0_0RCTRoundPixelValue(node->layout.position[CSS_TOP]),
  }, {
    ABI5_0_0RCTRoundPixelValue(absoluteBottomRight.x - absoluteTopLeft.x),
    ABI5_0_0RCTRoundPixelValue(absoluteBottomRight.y - absoluteTopLeft.y)
  }};

  if (!CGRectEqualToRect(frame, _frame)) {
    _frame = frame;
    [viewsWithNewFrame addObject:self];
  }

  absolutePosition.x += node->layout.position[CSS_LEFT];
  absolutePosition.y += node->layout.position[CSS_TOP];

  for (int i = 0; i < node->children_count; ++i) {
    ABI5_0_0RCTShadowView *child = (ABI5_0_0RCTShadowView *)_ReactABI5_0_0Subviews[i];
    [child applyLayoutNode:node->get_child(node->context, i)
         viewsWithNewFrame:viewsWithNewFrame
          absolutePosition:absolutePosition];
  }
}

- (NSDictionary<NSString *, id> *)processUpdatedProperties:(NSMutableSet<ABI5_0_0RCTApplierBlock> *)applierBlocks
                                          parentProperties:(NSDictionary<NSString *, id> *)parentProperties
{
  // TODO: we always refresh all propagated properties when propagation is
  // dirtied, but really we should track which properties have changed and
  // only update those.

  if (!_backgroundColor) {
    UIColor *parentBackgroundColor = parentProperties[ABI5_0_0RCTBackgroundColorProp];
    if (parentBackgroundColor) {
      [applierBlocks addObject:^(NSDictionary<NSNumber *, UIView *> *viewRegistry) {
        UIView *view = viewRegistry[_ReactABI5_0_0Tag];
        [view ReactABI5_0_0SetInheritedBackgroundColor:parentBackgroundColor];
      }];
    }
  } else {
    // Update parent properties for children
    NSMutableDictionary<NSString *, id> *properties = [NSMutableDictionary dictionaryWithDictionary:parentProperties];
    CGFloat alpha = CGColorGetAlpha(_backgroundColor.CGColor);
    if (alpha < 1.0) {
      // If bg is non-opaque, don't propagate further
      properties[ABI5_0_0RCTBackgroundColorProp] = [UIColor clearColor];
    } else {
      properties[ABI5_0_0RCTBackgroundColorProp] = _backgroundColor;
    }
    return properties;
  }
  return parentProperties;
}

- (void)collectUpdatedProperties:(NSMutableSet<ABI5_0_0RCTApplierBlock> *)applierBlocks
                parentProperties:(NSDictionary<NSString *, id> *)parentProperties
{
  if (_propagationLifecycle == ABI5_0_0RCTUpdateLifecycleComputed && [parentProperties isEqualToDictionary:_lastParentProperties]) {
    return;
  }
  _propagationLifecycle = ABI5_0_0RCTUpdateLifecycleComputed;
  _lastParentProperties = parentProperties;
  NSDictionary<NSString *, id> *nextProps = [self processUpdatedProperties:applierBlocks parentProperties:parentProperties];
  for (ABI5_0_0RCTShadowView *child in _ReactABI5_0_0Subviews) {
    [child collectUpdatedProperties:applierBlocks parentProperties:nextProps];
  }
}

- (CGRect)measureLayoutRelativeToAncestor:(ABI5_0_0RCTShadowView *)ancestor
{
  CGPoint offset = CGPointZero;
  NSInteger depth = 30; // max depth to search
  ABI5_0_0RCTShadowView *shadowView = self;
  while (depth && shadowView && shadowView != ancestor) {
    offset.x += shadowView.frame.origin.x;
    offset.y += shadowView.frame.origin.y;
    shadowView = shadowView->_superview;
    depth--;
  }
  if (ancestor != shadowView) {
    return CGRectNull;
  }
  return (CGRect){offset, self.frame.size};
}

- (instancetype)init
{
  if ((self = [super init])) {

    _frame = CGRectMake(0, 0, CSS_UNDEFINED, CSS_UNDEFINED);

    for (unsigned int ii = 0; ii < META_PROP_COUNT; ii++) {
      _paddingMetaProps[ii] = CSS_UNDEFINED;
      _marginMetaProps[ii] = CSS_UNDEFINED;
      _borderMetaProps[ii] = CSS_UNDEFINED;
    }

    _newView = YES;
    _layoutLifecycle = ABI5_0_0RCTUpdateLifecycleUninitialized;
    _propagationLifecycle = ABI5_0_0RCTUpdateLifecycleUninitialized;
    _textLifecycle = ABI5_0_0RCTUpdateLifecycleUninitialized;

    _ReactABI5_0_0Subviews = [NSMutableArray array];

    _cssNode = new_css_node();
    _cssNode->context = (__bridge void *)self;
    _cssNode->print = ABI5_0_0RCTPrint;
    _cssNode->get_child = ABI5_0_0RCTGetChild;
    _cssNode->is_dirty = ABI5_0_0RCTIsDirty;
    [self fillCSSNode:_cssNode];
  }
  return self;
}

- (BOOL)isReactABI5_0_0RootView
{
  return ABI5_0_0RCTIsReactABI5_0_0RootView(self.ReactABI5_0_0Tag);
}

- (void)dealloc
{
  free_css_node(_cssNode);
}

- (void)dirtyLayout
{
  if (_layoutLifecycle != ABI5_0_0RCTUpdateLifecycleDirtied) {
    _layoutLifecycle = ABI5_0_0RCTUpdateLifecycleDirtied;
    [_superview dirtyLayout];
  }
}

- (BOOL)isLayoutDirty
{
  return _layoutLifecycle != ABI5_0_0RCTUpdateLifecycleComputed;
}

- (void)dirtyPropagation
{
  if (_propagationLifecycle != ABI5_0_0RCTUpdateLifecycleDirtied) {
    _propagationLifecycle = ABI5_0_0RCTUpdateLifecycleDirtied;
    [_superview dirtyPropagation];
  }
}

- (BOOL)isPropagationDirty
{
  return _propagationLifecycle != ABI5_0_0RCTUpdateLifecycleComputed;
}

- (void)dirtyText
{
  if (_textLifecycle != ABI5_0_0RCTUpdateLifecycleDirtied) {
    _textLifecycle = ABI5_0_0RCTUpdateLifecycleDirtied;
    [_superview dirtyText];
  }
}

- (BOOL)isTextDirty
{
  return _textLifecycle != ABI5_0_0RCTUpdateLifecycleComputed;
}

- (void)setTextComputed
{
  _textLifecycle = ABI5_0_0RCTUpdateLifecycleComputed;
}

- (void)insertReactABI5_0_0Subview:(ABI5_0_0RCTShadowView *)subview atIndex:(NSInteger)atIndex
{
  [_ReactABI5_0_0Subviews insertObject:subview atIndex:atIndex];
  _cssNode->children_count = (int)_ReactABI5_0_0Subviews.count;
  subview->_superview = self;
  [self dirtyText];
  [self dirtyLayout];
  [self dirtyPropagation];
}

- (void)removeReactABI5_0_0Subview:(ABI5_0_0RCTShadowView *)subview
{
  [subview dirtyText];
  [subview dirtyLayout];
  [subview dirtyPropagation];
  subview->_superview = nil;
  [_ReactABI5_0_0Subviews removeObject:subview];
  _cssNode->children_count = (int)_ReactABI5_0_0Subviews.count;
}

- (NSArray<ABI5_0_0RCTShadowView *> *)ReactABI5_0_0Subviews
{
  return _ReactABI5_0_0Subviews;
}

- (ABI5_0_0RCTShadowView *)ReactABI5_0_0Superview
{
  return _superview;
}

- (NSNumber *)ReactABI5_0_0TagAtPoint:(CGPoint)point
{
  for (ABI5_0_0RCTShadowView *shadowView in _ReactABI5_0_0Subviews) {
    if (CGRectContainsPoint(shadowView.frame, point)) {
      CGPoint relativePoint = point;
      CGPoint origin = shadowView.frame.origin;
      relativePoint.x -= origin.x;
      relativePoint.y -= origin.y;
      return [shadowView ReactABI5_0_0TagAtPoint:relativePoint];
    }
  }
  return self.ReactABI5_0_0Tag;
}

- (NSString *)description
{
  NSString *description = super.description;
  description = [[description substringToIndex:description.length - 1] stringByAppendingFormat:@"; viewName: %@; ReactABI5_0_0Tag: %@; frame: %@>", self.viewName, self.ReactABI5_0_0Tag, NSStringFromCGRect(self.frame)];
  return description;
}

- (void)addRecursiveDescriptionToString:(NSMutableString *)string atLevel:(NSUInteger)level
{
  for (NSUInteger i = 0; i < level; i++) {
    [string appendString:@"  | "];
  }

  [string appendString:self.description];
  [string appendString:@"\n"];

  for (ABI5_0_0RCTShadowView *subview in _ReactABI5_0_0Subviews) {
    [subview addRecursiveDescriptionToString:string atLevel:level + 1];
  }
}

- (NSString *)recursiveDescription
{
  NSMutableString *description = [NSMutableString string];
  [self addRecursiveDescriptionToString:description atLevel:0];
  return description;
}

// Margin

#define ABI5_0_0RCT_MARGIN_PROPERTY(prop, metaProp)       \
- (void)setMargin##prop:(CGFloat)value            \
{                                                 \
  _marginMetaProps[META_PROP_##metaProp] = value; \
  _recomputeMargin = YES;                         \
}                                                 \
- (CGFloat)margin##prop                           \
{                                                 \
  return _marginMetaProps[META_PROP_##metaProp];  \
}

ABI5_0_0RCT_MARGIN_PROPERTY(, ALL)
ABI5_0_0RCT_MARGIN_PROPERTY(Vertical, VERTICAL)
ABI5_0_0RCT_MARGIN_PROPERTY(Horizontal, HORIZONTAL)
ABI5_0_0RCT_MARGIN_PROPERTY(Top, TOP)
ABI5_0_0RCT_MARGIN_PROPERTY(Left, LEFT)
ABI5_0_0RCT_MARGIN_PROPERTY(Bottom, BOTTOM)
ABI5_0_0RCT_MARGIN_PROPERTY(Right, RIGHT)

// Padding

#define ABI5_0_0RCT_PADDING_PROPERTY(prop, metaProp)       \
- (void)setPadding##prop:(CGFloat)value            \
{                                                  \
  _paddingMetaProps[META_PROP_##metaProp] = value; \
  _recomputePadding = YES;                         \
}                                                  \
- (CGFloat)padding##prop                           \
{                                                  \
  return _paddingMetaProps[META_PROP_##metaProp];  \
}

ABI5_0_0RCT_PADDING_PROPERTY(, ALL)
ABI5_0_0RCT_PADDING_PROPERTY(Vertical, VERTICAL)
ABI5_0_0RCT_PADDING_PROPERTY(Horizontal, HORIZONTAL)
ABI5_0_0RCT_PADDING_PROPERTY(Top, TOP)
ABI5_0_0RCT_PADDING_PROPERTY(Left, LEFT)
ABI5_0_0RCT_PADDING_PROPERTY(Bottom, BOTTOM)
ABI5_0_0RCT_PADDING_PROPERTY(Right, RIGHT)

- (UIEdgeInsets)paddingAsInsets
{
  return (UIEdgeInsets){
    _cssNode->style.padding[CSS_TOP],
    _cssNode->style.padding[CSS_LEFT],
    _cssNode->style.padding[CSS_BOTTOM],
    _cssNode->style.padding[CSS_RIGHT]
  };
}

// Border

#define ABI5_0_0RCT_BORDER_PROPERTY(prop, metaProp)            \
- (void)setBorder##prop##Width:(CGFloat)value          \
{                                                      \
  _borderMetaProps[META_PROP_##metaProp] = value;      \
  _recomputeBorder = YES;                              \
}                                                      \
- (CGFloat)border##prop##Width                         \
{                                                      \
  return _borderMetaProps[META_PROP_##metaProp];       \
}

ABI5_0_0RCT_BORDER_PROPERTY(, ALL)
ABI5_0_0RCT_BORDER_PROPERTY(Top, TOP)
ABI5_0_0RCT_BORDER_PROPERTY(Left, LEFT)
ABI5_0_0RCT_BORDER_PROPERTY(Bottom, BOTTOM)
ABI5_0_0RCT_BORDER_PROPERTY(Right, RIGHT)

// Dimensions

#define ABI5_0_0RCT_DIMENSIONS_PROPERTY(setProp, getProp, cssProp, dimensions) \
- (void)set##setProp:(CGFloat)value                                    \
{                                                                      \
  _cssNode->style.dimensions[CSS_##cssProp] = value;                   \
  [self dirtyLayout];                                                  \
}                                                                      \
- (CGFloat)getProp                                                     \
{                                                                      \
  return _cssNode->style.dimensions[CSS_##cssProp];                    \
}

ABI5_0_0RCT_DIMENSIONS_PROPERTY(Width, width, WIDTH, dimensions)
ABI5_0_0RCT_DIMENSIONS_PROPERTY(Height, height, HEIGHT, dimensions)

// Position

#define ABI5_0_0RCT_POSITION_PROPERTY(setProp, getProp, cssProp) \
- (void)set##setProp:(CGFloat)value                      \
{                                                        \
  _cssNode->style.position[CSS_##cssProp] = value;       \
  [self dirtyLayout];                                    \
}                                                        \
- (CGFloat)getProp                                       \
{                                                        \
  return _cssNode->style.position[CSS_##cssProp];        \
}

ABI5_0_0RCT_POSITION_PROPERTY(Top, top, TOP)
ABI5_0_0RCT_POSITION_PROPERTY(Right, right, RIGHT)
ABI5_0_0RCT_POSITION_PROPERTY(Bottom, bottom, BOTTOM)
ABI5_0_0RCT_POSITION_PROPERTY(Left, left, LEFT)

- (void)setFrame:(CGRect)frame
{
  _cssNode->style.position[CSS_LEFT] = CGRectGetMinX(frame);
  _cssNode->style.position[CSS_TOP] = CGRectGetMinY(frame);
  _cssNode->style.dimensions[CSS_WIDTH] = CGRectGetWidth(frame);
  _cssNode->style.dimensions[CSS_HEIGHT] = CGRectGetHeight(frame);
  [self dirtyLayout];
}

static inline BOOL ABI5_0_0RCTAssignSuggestedDimension(css_node_t *css_node, int dimension, CGFloat amount)
{
  if (amount != UIViewNoIntrinsicMetric
      && isnan(css_node->style.dimensions[dimension])) {
    css_node->style.dimensions[dimension] = amount;
    return YES;
  }
  return NO;
}

- (void)setIntrinsicContentSize:(CGSize)size
{
  if (_cssNode->style.flex == 0) {
    BOOL dirty = NO;
    dirty |= ABI5_0_0RCTAssignSuggestedDimension(_cssNode, CSS_HEIGHT, size.height);
    dirty |= ABI5_0_0RCTAssignSuggestedDimension(_cssNode, CSS_WIDTH, size.width);
    if (dirty) {
      [self dirtyLayout];
    }
  }
}

- (void)setTopLeft:(CGPoint)topLeft
{
  _cssNode->style.position[CSS_LEFT] = topLeft.x;
  _cssNode->style.position[CSS_TOP] = topLeft.y;
  [self dirtyLayout];
}

- (void)setSize:(CGSize)size
{
  _cssNode->style.dimensions[CSS_WIDTH] = size.width;
  _cssNode->style.dimensions[CSS_HEIGHT] = size.height;
  [self dirtyLayout];
}

// Flex

#define ABI5_0_0RCT_STYLE_PROPERTY(setProp, getProp, cssProp, type) \
- (void)set##setProp:(type)value                            \
{                                                           \
  _cssNode->style.cssProp = value;                          \
  [self dirtyLayout];                                       \
}                                                           \
- (type)getProp                                             \
{                                                           \
  return _cssNode->style.cssProp;                           \
}

ABI5_0_0RCT_STYLE_PROPERTY(Flex, flex, flex, CGFloat)
ABI5_0_0RCT_STYLE_PROPERTY(FlexDirection, flexDirection, flex_direction, css_flex_direction_t)
ABI5_0_0RCT_STYLE_PROPERTY(JustifyContent, justifyContent, justify_content, css_justify_t)
ABI5_0_0RCT_STYLE_PROPERTY(AlignSelf, alignSelf, align_self, css_align_t)
ABI5_0_0RCT_STYLE_PROPERTY(AlignItems, alignItems, align_items, css_align_t)
ABI5_0_0RCT_STYLE_PROPERTY(Position, position, position_type, css_position_type_t)
ABI5_0_0RCT_STYLE_PROPERTY(FlexWrap, flexWrap, flex_wrap, css_wrap_type_t)

- (void)setBackgroundColor:(UIColor *)color
{
  _backgroundColor = color;
  [self dirtyPropagation];
}

- (void)didSetProps:(__unused NSArray<NSString *> *)changedProps
{
  if (_recomputePadding) {
    ABI5_0_0RCTProcessMetaProps(_paddingMetaProps, _cssNode->style.padding);
  }
  if (_recomputeMargin) {
    ABI5_0_0RCTProcessMetaProps(_marginMetaProps, _cssNode->style.margin);
  }
  if (_recomputeBorder) {
    ABI5_0_0RCTProcessMetaProps(_borderMetaProps, _cssNode->style.border);
  }
  if (_recomputePadding || _recomputeMargin || _recomputeBorder) {
    [self dirtyLayout];
  }
  [self fillCSSNode:_cssNode];
  _recomputeMargin = NO;
  _recomputePadding = NO;
  _recomputeBorder = NO;
}

@end
