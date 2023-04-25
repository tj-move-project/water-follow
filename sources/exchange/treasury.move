module swap::treasury {

    friend swap::factory;

    struct Treasury has store {
        /// the address of the treasurer of the treasury
        treasurer: address,
    }

    /// We only allow this function to be called by the module factory.
    /// This is to ensure that only a single resource represents the AMM's treasury
    /// It should also only be called once in the init function
    public(friend) fun new(treasurer: address): Treasury {
        Treasury {
            treasurer,
        }
    }

    /// Returns the treasurer of the treasury
    public fun treasurer(treasury: &Treasury): address {
        treasury.treasurer
    }

    /// Appoints a new treasurer to the treasury
    public fun appoint(treasury: &mut Treasury, treasurer: address) {
        treasury.treasurer = treasurer;
    }

    #[test_only]
    public fun dummy(treasurer: address): Treasury {
        Treasury {
            treasurer,
        }
    }

    #[test_only]
    public fun destroy_for_testing(treasury: Treasury) {
        let Treasury {treasurer: _} = treasury;
    }

    #[test]
    fun test_appoint() {
        let alice = @0xa;
        let bob = @0xb;

        let treasury = new(alice);
        assert!(treasurer(&treasury) == alice, 1);

        appoint(&mut treasury, bob);
        assert!(treasurer(&treasury) == bob, 1);
        let Treasury {treasurer: _} = treasury;
    }
}