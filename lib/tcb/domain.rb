module TCB
  module Domain
    def self.included(base)
      base.include(HandlesEvents)
      base.include(HandlesCommands)
    end
  end
end
