-- //////////////
-- state
-- //////////////

function trigger_state(state_name, parent, machine_index)
	local parent = parent or player;
	local parent_state = parent.state
	local i = machine_index or 1
	local machine = parent_state.state_machines[i]

	if machine and machine[state_name] then
		parent_state.current_states[i] = state_name
		parent_state:run_state(machine[state_name], parent, i);
	end
end

compos.state = {
	last_states = {},
	is_active = function(self, state)
		for i = 1, #self.state_machines do
			for k, v in pairs(self.state_machines[i]) do
				if (self.current_states[i] == k and k == state) return true
			end
		end
		return false
	end,
	init = function(self, parent)
		self.current_states = parent.default_states or {}
		self.state_machines = #parent.states > 0 and parent.states or { parent.states }
	end,
	run_state = function(self, state, parent, machine_index)
		if state ~= self.last_states[machine_index] then
			self.last_states[machine_index] = state
			if (state[1]) state[1](parent) -- init
		end
		if (state[2]) state[2](parent) --update
	end,
	state_update = function(self, parent)
		local machines = self.state_machines

		if machines and #self.current_states > 0 then
			for i = 1, #machines do
				local machine = machines[i];
				local current_name = self.current_states[i];
				local current_state = machine[current_name]

				if (log_states) log(parent.tag .. ': ' .. current_name)

				if current_state then
					self:run_state(current_state, parent, i)
				end
			end
		end
	end
}
