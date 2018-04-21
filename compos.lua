-- ======================================z=================
-- helper functions
-- =======================================================
require('core/core')
require('core/debugging')
require('core/drawing')

-- =======================================================
-- components (compos!)
-- =======================================================

require('components/parallax')
require('components/health')
require('components/velocity')
require('components/collider')
require('components/gravity')
require('components/sprite')
require('components/age')
require('components/patrol')
require('components/state')

-->8
-- your code here!
function _init()
    cls()
    color(12)
    print('\n\n\n\n\nwelcome to compos!\nhack this cart by adding your\ncode to tab #1, include\nspecific components using\npicotool, or hack\none of the demos in this repo.')
    color(8)
    print('\n\nhave fun!')

    compos_init()
end

function _update()
    compos_update()
end

function _draw()
    compos_draw()
end