require('core/core')

function _init()
    compos_init()

    add_actor({
        init = function(self)
            self.text = 'hello, world!'
        end,
        update = function(self)
            self.y = 64 + sin(time()/3) * 30
        end,
        draw = function(self)
            print(self.text, 64 - #self.text * 2, self.y, 7, 8)
        end
    })
end

function _update()
    compos_update()
end

function _draw()
    cls()
    compos_draw()
end
