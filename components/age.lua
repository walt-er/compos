-- //////////////
-- age
-- //////////////

compos.age = {
	init = function(self, parent)
		self.birth, self.death = time(), 1  --default to one second
	end,
    set = function(self, death)
        self.birth, self.death = time(), death
    end,
    update = function(self, parent)
        if self.birth and time() - self.birth > self.death then
            remove_actor(parent)
        end
    end
}
