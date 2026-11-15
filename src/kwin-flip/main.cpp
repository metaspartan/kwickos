#include "flipeffect.h"

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED(FlipEffect,
                              "metadata.json",
                              return FlipEffect::supported();)

}

#include "main.moc"
