#include "liquidglasseffect.h"

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED(LiquidGlassEffect,
                              "metadata.json",
                              return LiquidGlassEffect::supported();)

}

#include "main.moc"
