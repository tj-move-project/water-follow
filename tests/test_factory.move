#[test_only]
module swap::test_factory {
    use sui::test_scenario;
    
    use swap::pair;
    use swap::factory::{Self, Container};

    struct USDT has drop {}
    
    struct DAI has drop {}

    #[test]
    fun test_create_pair() {
        let alice = @0xA;
        let scenario = test_scenario::begin(alice);
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            assert!(!factory::pair_is_created<USDT, DAI>(&container), 0);
            factory::create_pair<USDT, DAI>(&mut container, test_scenario::ctx(&mut scenario));
            assert!(factory::pair_is_created<USDT, DAI>(&container), 0);

            let usdt_dai = factory::borrow_pair<DAI, USDT>(&container);
            assert!(pair::total_lp_supply(usdt_dai) == 0, 1);
            let (reserve_x, reserve_y) = pair::get_reserves<DAI, USDT>(usdt_dai);
            assert!(reserve_x == 0 && reserve_y == 0, 1);

            test_scenario::return_shared(container);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = factory::ERROR_PAIR_ALREADY_CREATED)]
    fun test_create_pair_fail_if_pair_already_created() {
        let alice = @0xA;
        let scenario = test_scenario::begin(alice);
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            factory::create_pair<USDT, DAI>(&mut container, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            factory::create_pair<USDT, DAI>(&mut container, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(container);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = factory::ERROR_PAIR_ALREADY_CREATED)]
    fun test_create_pair_fail_if_pair_already_created_reserve_order() {
        let alice = @0xA;
        let scenario = test_scenario::begin(alice);
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            factory::create_pair<USDT, DAI>(&mut container, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            factory::create_pair<DAI, USDT>(&mut container, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(container);
        };

        test_scenario::end(scenario);
    }
}