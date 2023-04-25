#[test_only]
module swap::test_router {
    use sui::object;
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, Scenario};
    use sui::clock;
    
    use swap::pair::{Self, LP};
    use swap::factory::{Self, Container};
    use swap::router;

    struct USDT has drop {}

    struct DAI has drop {} 
    
    struct ETH has drop {}

    struct BTC has drop {}

    struct SOL has drop {}

    struct BNB has drop {}

    const MINIMUM_LIQUIDITY: u64 = 1000;

    #[test_only]
    public fun add_liquidity<X, Y>(container: &mut Container, amount_x: u64, amount_y: u64, to: address, scenario: &mut Scenario) {
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        let x = coin::mint_for_testing<X>(amount_x, test_scenario::ctx(scenario));
        let y = coin::mint_for_testing<Y>(amount_y, test_scenario::ctx(scenario));

        router::add_liquidity<X, Y>(&clock, container, x, y, amount_x, amount_y, to, 99, test_scenario::ctx(scenario));
        clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_add_liquidity() {
        let alice = @0xA;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {   
            let usdt = coin::mint_for_testing<USDT>(1000000000, test_scenario::ctx(&mut scenario));
            let dai = coin::mint_for_testing<DAI>(4000000000, test_scenario::ctx(&mut scenario));
            let container = test_scenario::take_shared<Container>(&scenario);
            router::add_liquidity<USDT, DAI>(&clock, &mut container, usdt, dai, 1000000000, 4000000000, alice, 99, test_scenario::ctx(&mut scenario));

            let pair = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(pair);
            assert!(resevse_dai == 4000000000 && resevse_usdt == 1000000000, 0);
            assert!(pair::total_lp_supply<DAI, USDT>(pair) == 2000000000, 0);

            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, alice);
        {
            let lp = test_scenario::take_from_address<Coin<LP<DAI, USDT>>>(&scenario, alice);
            assert!(coin::value(&lp) == (2000000000 - MINIMUM_LIQUIDITY), 0);
            test_scenario::return_to_address(alice, lp);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_remove_liquidity() {
        let alice = @0xA;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        let first_id;
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 1000000000, 4000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };
        test_scenario::next_tx(&mut scenario, alice);
        {
            let lp = test_scenario::take_from_address<Coin<LP<DAI, USDT>>>(&scenario, alice);
            first_id = object::id(&lp);
            test_scenario::return_to_address(alice, lp);
        };

        let second_id;
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 2000000000, 8000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };
        test_scenario::next_tx(&mut scenario, alice);
        {
            let lp = test_scenario::take_from_address<Coin<LP<DAI, USDT>>>(&scenario, alice);
            second_id = object::id(&lp);
            test_scenario::return_to_address(alice, lp);
        };

        test_scenario::next_tx(&mut scenario, alice);
        {
            let first_lp = test_scenario::take_from_address_by_id<Coin<LP<DAI, USDT>>>(&scenario, alice, first_id);
            assert!(coin::value(&first_lp) == 1999999000, 0);
            let second_lp = test_scenario::take_from_address_by_id<Coin<LP<DAI, USDT>>>(&scenario, alice, second_id);
            assert!(coin::value(&second_lp) == 4000000000, 0);

            let container = test_scenario::take_shared<Container>(&scenario);
            let amount_lp_desired = 5000000000;
            let amount_usdt_mint = 2500000000;
            let amount_dai_mint = 10000000000;
            coin::join<LP<DAI, USDT>>(&mut first_lp, second_lp);
            let lp_desired = coin::split<LP<DAI, USDT>>(&mut first_lp, amount_lp_desired, test_scenario::ctx(&mut scenario));
            router::remove_liquidity<DAI, USDT>(&clock, &mut container, lp_desired, amount_dai_mint, amount_usdt_mint, alice, 99, test_scenario::ctx(&mut scenario));
            
            let pair = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(pair);
            assert!(resevse_usdt == 500000000 && resevse_dai == 2000000000, 0);
            assert!(pair::total_lp_supply<DAI, USDT>(pair) == 1000000000, 0);
            
            test_scenario::return_to_address(alice, first_lp);
            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, alice);
        { 
            assert!(!test_scenario::was_taken_from_address(alice, first_id), 0);
            assert!(!test_scenario::was_taken_from_address(alice, second_id), 0);

            let usdt = test_scenario::take_from_address<Coin<USDT>>(&scenario, alice);
            assert!(coin::value(&usdt) == 2500000000, 0);
            let dai = test_scenario::take_from_address<Coin<DAI>>(&scenario, alice);
            assert!(coin::value(&dai) == 10000000000, 0);
            let lp = test_scenario::take_from_address<Coin<LP<DAI, USDT>>>(&scenario, alice);
            assert!(coin::value(&lp) == 999999000, 0);

            test_scenario::return_to_address(alice, usdt);
            test_scenario::return_to_address(alice, dai);
            test_scenario::return_to_address(alice, lp);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_input() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 1000000000, 4000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };

        //Bob swap 100000000 USDT, receive: (4000000000 * 100000000*0.997)/(1000000000 + 100000000*0.997) = 362644357 DAI
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(100000000, test_scenario::ctx(&mut scenario));
            let amount_dai_min_out = 362644357;
            
            router::swap_exact_input<USDT, DAI>(&clock, &mut container, usdt, amount_dai_min_out, bob, 99, test_scenario::ctx(&mut scenario));
            let pair = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(pair);
            assert!(resevse_dai == 3637355643 && resevse_usdt == 1100000000, 0);

            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let dai = test_scenario::take_from_address<Coin<DAI>>(&scenario, bob);
            assert!(coin::value(&dai) == 362644357, 0);
            test_scenario::return_to_address(bob, dai);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_input_doublehop() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 1000000000, 4000000000, alice, &mut scenario);
            add_liquidity<DAI, ETH>(&mut container, 10000000000, 1000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };

        //Bob swap 100000000 USDT to ETH, receive:
        //(4000000000 * 100000000*0.997)/(1000000000 + 100000000*0.997) = 362644357 DAI
        //(1000000000 * 362644357*0.997)/(10000000000 + 362644357*0.997) = 34894026 ETH
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(100000000, test_scenario::ctx(&mut scenario));
            let amount_eth_min_out = 34894026;

            router::swap_exact_input_doublehop<USDT, DAI, ETH>(&clock, &mut container, usdt, amount_eth_min_out, bob, 99, test_scenario::ctx(&mut scenario));
            let usdt_dai = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(usdt_dai);
            assert!(resevse_dai == 3637355643 && resevse_usdt == 1100000000, 0);

            let dai_eth = factory::borrow_pair<DAI, ETH>(&container);
            let (resevse_dai, resevse_eth) = pair::get_reserves<DAI, ETH>(dai_eth);
            assert!(resevse_dai == 10362644357 && resevse_eth == 965105974, 0);

            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let eth = test_scenario::take_from_address<Coin<ETH>>(&scenario, bob);
            assert!(coin::value(&eth) == 34894026, 0);
            test_scenario::return_to_address(bob, eth);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_input_triplehop() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 1000000000, 4000000000, alice, &mut scenario);
            add_liquidity<DAI, ETH>(&mut container, 10000000000, 1000000000, alice, &mut scenario);
            add_liquidity<ETH, BTC>(&mut container, 5000000000, 1000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };

        //Bob swap 100000000 USDT to BTC, receive:
        //(4000000000 * 100000000*0.997)/(1000000000 + 100000000*0.997) = 362644357 DAI
        //(1000000000 * 362644357*0.997)/(10000000000 + 362644357*0.997) = 34894026 ETH
        //(1000000000 * 34894026*0.997)/(5000000000 + 34894026*0.997) = 6909791 BTC
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(100000000, test_scenario::ctx(&mut scenario));
            let amount_btc_min_out = 6909791;  

            router::swap_exact_input_triplehop<USDT, DAI, ETH, BTC>(&clock, &mut container, usdt, amount_btc_min_out, bob, 99, test_scenario::ctx(&mut scenario));
            let usdt_dai = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(usdt_dai);
            assert!(resevse_dai == 3637355643 && resevse_usdt == 1100000000, 0);

            let dai_eth = factory::borrow_pair<DAI, ETH>(&container);
            let (resevse_dai, resevse_eth) = pair::get_reserves<DAI, ETH>(dai_eth);
            assert!(resevse_dai == 10362644357 && resevse_eth == 965105974, 0);

            let btc_eth = factory::borrow_pair<BTC, ETH>(&container);
            let (resevse_btc, resevse_eth) = pair::get_reserves<BTC, ETH>(btc_eth);
            assert!(resevse_btc == 993090209 && resevse_eth == 5034894026, 0);

            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let btc = test_scenario::take_from_address<Coin<BTC>>(&scenario, bob);
            assert!(coin::value(&btc) == 6909791, 0);
            test_scenario::return_to_address(bob, btc);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_input_double_output(){
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 1000000000, 4000000000, alice, &mut scenario);
            add_liquidity<USDT, ETH>(&mut container, 10000000000, 1000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };

        //Bob swap 100000000 USDT to DAI and 200000000 USDT to ETH, Alice should have receive:
        //(4000000000 * 100000000*0.997)/(1000000000 + 100000000*0.997) = 362644357 DAI
        //(1000000000 * 200000000*0.997)/(10000000000 + 200000000*0.997) = 19550169 ETH
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(300000000, test_scenario::ctx(&mut scenario));

            router::swap_exact_input_double_output<USDT, DAI, ETH>(&clock, &mut container, usdt, 100000000, 200000000, 362644357, 19550169, bob, 99, test_scenario::ctx(&mut scenario));
            let usdt_dai = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(usdt_dai);
            assert!(resevse_dai == 3637355643 && resevse_usdt == 1100000000, 0);

            let usdt_eth = factory::borrow_pair<ETH, USDT>(&container);
            let (resevse_eth, resevse_usdt) = pair::get_reserves<ETH, USDT>(usdt_eth);
            assert!(resevse_eth == 980449831 && resevse_usdt == 10200000000, 0);
            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let dai = test_scenario::take_from_address<Coin<DAI>>(&scenario, bob);
            assert!(coin::value(&dai) == 362644357, 0);
            test_scenario::return_to_address(bob, dai);

            let eth = test_scenario::take_from_address<Coin<ETH>>(&scenario, bob);
            assert!(coin::value(&eth) == 19550169, 0);
            test_scenario::return_to_address(bob, eth);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_input_triple_output(){
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 1000000000, 4000000000, alice, &mut scenario);
            add_liquidity<USDT, ETH>(&mut container, 10000000000, 1000000000, alice, &mut scenario);
            add_liquidity<USDT, BTC>(&mut container, 50000000000, 1000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };

        //Bob swap 100000000 USDT to DAI, 200000000 USDT to ETH, 1500000000 to BTC Alice should have receive:
        //(4000000000 * 100000000*0.997)/(1000000000 + 100000000*0.997) = 362644357 DAI
        //(1000000000 * 200000000*0.997)/(10000000000 + 200000000*0.997) = 19550169 ETH
        //(1000000000 * 1500000000*0.997)/(50000000000 + 1500000000*0.997) = 29041372 BTC
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(1800000000, test_scenario::ctx(&mut scenario));

            router::swap_exact_input_triple_output<USDT, DAI, ETH, BTC>(&clock, &mut container, usdt, 100000000, 200000000, 1500000000, 362644357, 19550169, 29041372, bob, 99, test_scenario::ctx(&mut scenario));
            let usdt_dai = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(usdt_dai);
            assert!(resevse_dai == 3637355643 && resevse_usdt == 1100000000, 0);

            let usdt_eth = factory::borrow_pair<ETH, USDT>(&container);
            let (resevse_eth, resevse_usdt) = pair::get_reserves<ETH, USDT>(usdt_eth);
            assert!(resevse_eth == 980449831 && resevse_usdt == 10200000000, 0);

            let usdt_btc = factory::borrow_pair<BTC, USDT>(&container);
            let (resevse_btc, resevse_usdt) = pair::get_reserves<BTC, USDT>(usdt_btc);
            assert!(resevse_btc == 970958628 && resevse_usdt == 51500000000, 0);
            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let dai = test_scenario::take_from_address<Coin<DAI>>(&scenario, bob);
            assert!(coin::value(&dai) == 362644357, 0);
            test_scenario::return_to_address(bob, dai);

            let eth = test_scenario::take_from_address<Coin<ETH>>(&scenario, bob);
            assert!(coin::value(&eth) == 19550169, 0);
            test_scenario::return_to_address(bob, eth);

            let btc = test_scenario::take_from_address<Coin<BTC>>(&scenario, bob);
            assert!(coin::value(&btc) == 29041372, 0);
            test_scenario::return_to_address(bob, btc);
        };
        
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_input_quadruple_output(){
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 1000000000, 4000000000, alice, &mut scenario);
            add_liquidity<USDT, ETH>(&mut container, 10000000000, 1000000000, alice, &mut scenario);
            add_liquidity<USDT, BTC>(&mut container, 50000000000, 1000000000, alice, &mut scenario);
            add_liquidity<USDT, SOL>(&mut container, 20000000000, 10000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };

        //Bob swap 100000000 USDT to DAI, 200000000 USDT to ETH, 1500000000 to BTC, 500000000 USDT to SOL  Alice should have receive:
        //(4000000000 * 100000000*0.997)/(1000000000 + 100000000*0.997) = 362644357 DAI
        //(1000000000 * 200000000*0.997)/(10000000000 + 200000000*0.997) = 19550169 ETH
        //(1000000000 * 1500000000*0.997)/(50000000000 + 1500000000*0.997) = 29041372 BTC
        //(10000000000 * 500000000*0.997)/(20000000000 + 500000000*0.997) = 243188525 SOL
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(2300000000, test_scenario::ctx(&mut scenario));

            router::swap_exact_input_quadruple_output<USDT, DAI, ETH, BTC, SOL>(&clock, &mut container, usdt, 100000000, 200000000, 1500000000, 500000000,
             362644357, 19550169, 29041372, 243188525, bob, 99, test_scenario::ctx(&mut scenario));
            let usdt_dai = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(usdt_dai);
            assert!(resevse_dai == 3637355643 && resevse_usdt == 1100000000, 0);

            let usdt_eth = factory::borrow_pair<ETH, USDT>(&container);
            let (resevse_eth, resevse_usdt) = pair::get_reserves<ETH, USDT>(usdt_eth);
            assert!(resevse_eth == 980449831 && resevse_usdt == 10200000000, 0);

            let usdt_btc = factory::borrow_pair<BTC, USDT>(&container);
            let (resevse_btc, resevse_usdt) = pair::get_reserves<BTC, USDT>(usdt_btc);
            assert!(resevse_btc == 970958628 && resevse_usdt == 51500000000, 0);

            let usdt_sol = factory::borrow_pair<SOL, USDT>(&container);
            let (resevse_sol, resevse_usdt) = pair::get_reserves<SOL, USDT>(usdt_sol);
            assert!(resevse_sol == 9756811475 && resevse_usdt == 20500000000, 0);
            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let dai = test_scenario::take_from_address<Coin<DAI>>(&scenario, bob);
            assert!(coin::value(&dai) == 362644357, 0);
            test_scenario::return_to_address(bob, dai);

            let eth = test_scenario::take_from_address<Coin<ETH>>(&scenario, bob);
            assert!(coin::value(&eth) == 19550169, 0);
            test_scenario::return_to_address(bob, eth);

            let btc = test_scenario::take_from_address<Coin<BTC>>(&scenario, bob);
            assert!(coin::value(&btc) == 29041372, 0);
            test_scenario::return_to_address(bob, btc);

            let sol = test_scenario::take_from_address<Coin<SOL>>(&scenario, bob);
            assert!(coin::value(&sol) == 243188525, 0);
            test_scenario::return_to_address(bob, sol);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_input_quintuple_output(){
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 1000000000, 4000000000, alice, &mut scenario);
            add_liquidity<USDT, ETH>(&mut container, 10000000000, 1000000000, alice, &mut scenario);
            add_liquidity<USDT, BTC>(&mut container, 50000000000, 1000000000, alice, &mut scenario);
            add_liquidity<USDT, SOL>(&mut container, 20000000000, 10000000000, alice, &mut scenario);
            add_liquidity<USDT, BNB>(&mut container, 30000000000, 10000000000, alice, &mut scenario);

            test_scenario::return_shared(container);
        };

        //Bob swap 100000000 USDT to DAI, 200000000 USDT to ETH, 1500000000 to BTC, 500000000 USDT to SOL, 700000000 USDT to BNB Alice should have receive:
        //(4000000000 * 100000000*0.997)/(1000000000 + 100000000*0.997) = 362644357 DAI
        //(1000000000 * 200000000*0.997)/(10000000000 + 200000000*0.997) = 19550169 ETH
        //(1000000000 * 1500000000*0.997)/(50000000000 + 1500000000*0.997) = 29041372 BTC
        //(10000000000 * 500000000*0.997)/(20000000000 + 500000000*0.997) = 243188525 SOL
        //(10000000000 * 700000000*0.997)/(30000000000  + 700000000*0.997) = 227344541 BNB
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(3000000000, test_scenario::ctx(&mut scenario));

            router::swap_exact_input_quintuple_output<USDT, DAI, ETH, BTC, SOL, BNB>(&clock, &mut container, usdt,
             100000000, 200000000, 1500000000, 500000000, 700000000, 362644357, 19550169, 29041372, 243188525, 227344541, bob, 99, test_scenario::ctx(&mut scenario));
            let usdt_dai = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(usdt_dai);
            assert!(resevse_dai == 3637355643 && resevse_usdt == 1100000000, 0);

            let usdt_eth = factory::borrow_pair<ETH, USDT>(&container);
            let (resevse_eth, resevse_usdt) = pair::get_reserves<ETH, USDT>(usdt_eth);
            assert!(resevse_eth == 980449831 && resevse_usdt == 10200000000, 0);

            let usdt_btc = factory::borrow_pair<BTC, USDT>(&container);
            let (resevse_btc, resevse_usdt) = pair::get_reserves<BTC, USDT>(usdt_btc);
            assert!(resevse_btc == 970958628 && resevse_usdt == 51500000000, 0);

            let usdt_sol = factory::borrow_pair<SOL, USDT>(&container);
            let (resevse_sol, resevse_usdt) = pair::get_reserves<SOL, USDT>(usdt_sol);
            assert!(resevse_sol == 9756811475 && resevse_usdt == 20500000000, 0);

            let usdt_bnb = factory::borrow_pair<BNB, USDT>(&container);
            let (resevse_bnb, resevse_usdt) = pair::get_reserves<BNB, USDT>(usdt_bnb);
            assert!(resevse_bnb == 9772655459 && resevse_usdt == 30700000000, 0);
            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let dai = test_scenario::take_from_address<Coin<DAI>>(&scenario, bob);
            assert!(coin::value(&dai) == 362644357, 0);
            test_scenario::return_to_address(bob, dai);

            let eth = test_scenario::take_from_address<Coin<ETH>>(&scenario, bob);
            assert!(coin::value(&eth) == 19550169, 0);
            test_scenario::return_to_address(bob, eth);

            let btc = test_scenario::take_from_address<Coin<BTC>>(&scenario, bob);
            assert!(coin::value(&btc) == 29041372, 0);
            test_scenario::return_to_address(bob, btc);

            let sol = test_scenario::take_from_address<Coin<SOL>>(&scenario, bob);
            assert!(coin::value(&sol) == 243188525, 0);
            test_scenario::return_to_address(bob, sol);

            let bnb = test_scenario::take_from_address<Coin<BNB>>(&scenario, bob);
            assert!(coin::value(&bnb) == 227344541, 0);
            test_scenario::return_to_address(bob, bnb);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_swap_exact_double_input() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
       
        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, ETH>(&mut container, 4000000000, 1000000000, alice, &mut scenario);
            add_liquidity<DAI, ETH>(&mut container, 500000000, 1000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };

        //Bob swap 100000000 USDT to ETH, 200000000 DAI to ETH. Alice should have receive:
        //(1000000000 * 100000000*0.997)/(4000000000 + 100000000*0.997) = 24318852 ETH
        //(1000000000 * 200000000*0.997)/(500000000 + 200000000*0.997) = 285101515 ETH
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(100000000, test_scenario::ctx(&mut scenario));
            let dai = coin::mint_for_testing<DAI>(200000000, test_scenario::ctx(&mut scenario));

            router::swap_exact_double_input<USDT, DAI, ETH>(&clock, &mut container, usdt, dai, 309420367, bob, 99, test_scenario::ctx(&mut scenario));
            let usdt_eth = factory::borrow_pair<ETH, USDT>(&container);
            let (resevse_eth, resevse_usdt) = pair::get_reserves<ETH, USDT>(usdt_eth);
            assert!(resevse_eth == 975681148 && resevse_usdt == 4100000000, 0);

            let dai_eth = factory::borrow_pair<DAI, ETH>(&container);
            let (resevse_dai, resevse_eth) = pair::get_reserves<DAI, ETH>(dai_eth);
            assert!(resevse_dai == 700000000 && resevse_eth == 714898485, 0);

            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let eth = test_scenario::take_from_address<Coin<ETH>>(&scenario, bob);
            assert!(coin::value(&eth) == 309420367, 0);
            test_scenario::return_to_address(bob, eth);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_triple_input() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, ETH>(&mut container, 4000000000, 1000000000, alice, &mut scenario);
            add_liquidity<DAI, ETH>(&mut container, 500000000, 1000000000, alice, &mut scenario);
            add_liquidity<BTC, ETH>(&mut container, 1000000000, 10000000000, alice, &mut scenario);

            test_scenario::return_shared(container);
        };

        //Bob swap 100000000 USDT to ETH, 200000000 DAI to ETH, 300000000 BTC to ETH. Alice should have receive:
        //(1000000000 * 100000000*0.997)/(4000000000 + 100000000*0.997) = 24318852 ETH
        //(1000000000 * 200000000*0.997)/(500000000 + 200000000*0.997) = 285101515 ETH
        //(10000000000 * 300000000*0.997)/(1000000000 + 300000000*0.997) = 2302363174 ETH
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(100000000, test_scenario::ctx(&mut scenario));
            let dai = coin::mint_for_testing<DAI>(200000000, test_scenario::ctx(&mut scenario));
            let btc = coin::mint_for_testing<BTC>(300000000, test_scenario::ctx(&mut scenario));

            router::swap_exact_triple_input<USDT, DAI, BTC, ETH>(&clock, &mut container, usdt, dai, btc, 2611783541, bob, 99, test_scenario::ctx(&mut scenario));
            let usdt_eth = factory::borrow_pair<ETH, USDT>(&container);
            let (resevse_eth, resevse_usdt) = pair::get_reserves<ETH, USDT>(usdt_eth);
            assert!(resevse_eth == 975681148 && resevse_usdt == 4100000000, 0);

            let dai_eth = factory::borrow_pair<DAI, ETH>(&container);
            let (resevse_dai, resevse_eth) = pair::get_reserves<DAI, ETH>(dai_eth);
            assert!(resevse_dai == 700000000 && resevse_eth == 714898485, 0);

            let btc_eth = factory::borrow_pair<BTC, ETH>(&container);
            let (resevse_btc, resevse_eth) = pair::get_reserves<BTC, ETH>(btc_eth);
            assert!(resevse_btc == 1300000000 && resevse_eth == 7697636826, 0);

            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let eth = test_scenario::take_from_address<Coin<ETH>>(&scenario, bob);
            assert!(coin::value(&eth) == 2611783541, 0);
            test_scenario::return_to_address(bob, eth);
        };

        clock::destroy_for_testing(clock);       
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_quadruple_input() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, ETH>(&mut container, 4000000000, 1000000000, alice, &mut scenario);
            add_liquidity<DAI, ETH>(&mut container, 500000000, 1000000000, alice, &mut scenario);
            add_liquidity<BTC, ETH>(&mut container, 1000000000, 10000000000, alice, &mut scenario);
            add_liquidity<SOL, ETH>(&mut container, 7000000000, 1000000000, alice, &mut scenario);

            test_scenario::return_shared(container);
        };

        //Bob swap 100000000 USDT to ETH, 200000000 DAI to ETH, 300000000 BTC to ETH, 500000000 SOL to ETH Alice should have receive:
        //(1000000000 * 100000000*0.997)/(4000000000 + 100000000*0.997) = 24318852 ETH
        //(1000000000 * 200000000*0.997)/(500000000 + 200000000*0.997) = 285101515 ETH
        //(10000000000 * 300000000*0.997)/(1000000000 + 300000000*0.997) = 2302363174 ETH
        //(1000000000 * 500000000*0.997)/(7000000000 + 500000000*0.997) = 66479962 ETH
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(100000000, test_scenario::ctx(&mut scenario));
            let dai = coin::mint_for_testing<DAI>(200000000, test_scenario::ctx(&mut scenario));
            let btc = coin::mint_for_testing<BTC>(300000000, test_scenario::ctx(&mut scenario));
            let sol = coin::mint_for_testing<SOL>(500000000, test_scenario::ctx(&mut scenario));

            router::swap_exact_quadruple_input<USDT, DAI, BTC, SOL, ETH>(&clock, &mut container, usdt, dai, btc, sol,
             2678263503, bob, 99, test_scenario::ctx(&mut scenario));
            let usdt_eth = factory::borrow_pair<ETH, USDT>(&container);
            let (resevse_eth, resevse_usdt) = pair::get_reserves<ETH, USDT>(usdt_eth);
            assert!(resevse_eth == 975681148 && resevse_usdt == 4100000000, 0);

            let dai_eth = factory::borrow_pair<DAI, ETH>(&container);
            let (resevse_dai, resevse_eth) = pair::get_reserves<DAI, ETH>(dai_eth);
            assert!(resevse_dai == 700000000 && resevse_eth == 714898485, 0);

            let btc_eth = factory::borrow_pair<BTC, ETH>(&container);
            let (resevse_btc, resevse_eth) = pair::get_reserves<BTC, ETH>(btc_eth);
            assert!(resevse_btc == 1300000000 && resevse_eth == 7697636826, 0);

            let sol_eth = factory::borrow_pair<ETH, SOL>(&container);
            let (resevse_eth, resevse_sol) = pair::get_reserves<ETH, SOL>(sol_eth);
            assert!(resevse_eth == 933520038 && resevse_sol == 7500000000, 0);
            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let eth = test_scenario::take_from_address<Coin<ETH>>(&scenario, bob);
            assert!(coin::value(&eth) == 2678263503, 0);
            test_scenario::return_to_address(bob, eth);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_quintuple_input() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, ETH>(&mut container, 4000000000, 1000000000, alice, &mut scenario);
            add_liquidity<DAI, ETH>(&mut container, 500000000, 1000000000, alice, &mut scenario);
            add_liquidity<BTC, ETH>(&mut container, 1000000000, 10000000000, alice, &mut scenario);
            add_liquidity<SOL, ETH>(&mut container, 7000000000, 1000000000, alice, &mut scenario);
            add_liquidity<BNB, ETH>(&mut container, 3000000000, 1000000000, alice, &mut scenario);

            test_scenario::return_shared(container);
        };

        //Bob swap 100000000 USDT to ETH, 200000000 DAI to ETH, 300000000 BTC to ETH, 500000000 SOL to ETH, 700000000 BNB to ETH. Alice should have receive:
        //(1000000000 * 100000000*0.997)/(4000000000 + 100000000*0.997) = 24318852 ETH
        //(1000000000 * 200000000*0.997)/(500000000 + 200000000*0.997) = 285101515 ETH
        //(10000000000 * 300000000*0.997)/(1000000000 + 300000000*0.997) = 2302363174 ETH
        //(1000000000 * 500000000*0.997)/(7000000000 + 500000000*0.997) = 66479962 ETH
        //(1000000000 * 700000000*0.997)/(3000000000 + 700000000*0.997) = 188728737 ETH
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(100000000, test_scenario::ctx(&mut scenario));
            let dai = coin::mint_for_testing<DAI>(200000000, test_scenario::ctx(&mut scenario));
            let btc = coin::mint_for_testing<BTC>(300000000, test_scenario::ctx(&mut scenario));
            let sol = coin::mint_for_testing<SOL>(500000000, test_scenario::ctx(&mut scenario));
            let bnb = coin::mint_for_testing<BNB>(700000000, test_scenario::ctx(&mut scenario));

            router::swap_exact_quintuple_input<USDT, DAI, BTC, SOL, BNB, ETH>(&clock, &mut container, usdt, dai, btc, sol, bnb,
            2866992240, bob, 99, test_scenario::ctx(&mut scenario));
            let usdt_eth = factory::borrow_pair<ETH, USDT>(&container);
            let (resevse_eth, resevse_usdt) = pair::get_reserves<ETH, USDT>(usdt_eth);
            assert!(resevse_eth == 975681148 && resevse_usdt == 4100000000, 0);

            let dai_eth = factory::borrow_pair<DAI, ETH>(&container);
            let (resevse_dai, resevse_eth) = pair::get_reserves<DAI, ETH>(dai_eth);
            assert!(resevse_dai == 700000000 && resevse_eth == 714898485, 0);

            let btc_eth = factory::borrow_pair<BTC, ETH>(&container);
            let (resevse_btc, resevse_eth) = pair::get_reserves<BTC, ETH>(btc_eth);
            assert!(resevse_btc == 1300000000 && resevse_eth == 7697636826, 0);

            let sol_eth = factory::borrow_pair<ETH, SOL>(&container);
            let (resevse_eth, resevse_sol) = pair::get_reserves<ETH, SOL>(sol_eth);
            assert!(resevse_eth == 933520038 && resevse_sol == 7500000000, 0);
            
            let bnb_eth = factory::borrow_pair<BNB, ETH>(&container);
            let (resevse_bnb, resevse_eth) = pair::get_reserves<BNB, ETH>(bnb_eth);
            assert!(resevse_bnb == 3700000000 && resevse_eth == 811271263, 0);

            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let eth = test_scenario::take_from_address<Coin<ETH>>(&scenario, bob);
            assert!(coin::value(&eth) == 2866992240, 0);
            test_scenario::return_to_address(bob, eth);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_output() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 1000000000, 4000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };

        //Bob want to receive 1000000000 DAI
        //Minimum amount of USDT that can be deposited is ((1000000000 * 1000000000) / (4000000000 - 1000000000)) / 0.997 = 334336343
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(400000000, test_scenario::ctx(&mut scenario));
            let amount_usdt_max = 334336343;
            let amount_dai_out = 1000000000;

            router::swap_exact_output<USDT, DAI>(&clock, &mut container, usdt, amount_usdt_max, amount_dai_out, bob, 99, test_scenario::ctx(&mut scenario));
            let pair = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(pair);
            assert!(resevse_dai == 3000000000 && resevse_usdt == 1334336343, 0);

            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let dai = test_scenario::take_from_address<Coin<DAI>>(&scenario, bob);
            assert!(coin::value(&dai) == 1000000000, 0);
            let usdt = test_scenario::take_from_address<Coin<USDT>>(&scenario, bob);
            assert!(coin::value(&usdt) == 65663657, 0);

            test_scenario::return_to_address(bob, dai);
            test_scenario::return_to_address(bob, usdt); 
        };


        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_output_doublehop() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
       
        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 1000000000, 4000000000, alice, &mut scenario);
            add_liquidity<DAI, ETH>(&mut container, 10000000000, 1000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };

        //Bob want to receive 0.1 ETH
        //Minimum amount of DAI that can be deposited is ((10000000000 * 100000000) / (1000000000 - 100000000)) / 0.997 + 1 = 1114454475
        //Minimum amount of USDT that can be deposited is ((1000000000 * 1114454475) / (4000000000 - 1114454475)) / 0.997 + 1 = 387381828
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(387381829, test_scenario::ctx(&mut scenario));
            let amount_usdt_max = 387381828;
            let amount_eth_out = 100000000;

            router::swap_exact_output_doublehop<USDT, DAI, ETH>(&clock, &mut container, usdt, amount_usdt_max, amount_eth_out, bob, 99, test_scenario::ctx(&mut scenario));
            let dai_usdt = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(dai_usdt);
            assert!(resevse_dai == 2885545525 && resevse_usdt == 1387381828, 0);

            let dai_eth = factory::borrow_pair<DAI, ETH>(&container);
            let (resevse_dai, resevse_eth) = pair::get_reserves<DAI, ETH>(dai_eth);
            assert!(resevse_dai == 11114454475 && resevse_eth == 900000000, 0);

            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let eth = test_scenario::take_from_address<Coin<ETH>>(&scenario, bob);
            assert!(coin::value(&eth) == 100000000, 0);
            let usdt = test_scenario::take_from_address<Coin<USDT>>(&scenario, bob);
            assert!(coin::value(&usdt) == 1, 0);

            test_scenario::return_to_address(bob, eth);
            test_scenario::return_to_address(bob, usdt);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_exact_output_triplehop() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, alice);
        {
            factory::dummy(test_scenario::ctx(&mut scenario));
        };
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            add_liquidity<USDT, DAI>(&mut container, 2000000000, 20000000000, alice, &mut scenario);
            add_liquidity<DAI, ETH>(&mut container, 10000000000, 1000000000, alice, &mut scenario);
            add_liquidity<ETH, BTC>(&mut container, 5000000000, 1000000000, alice, &mut scenario);
            test_scenario::return_shared(container);
        };

        //Bob want to receive 0.1 BTC
        //Minimum amount of ETH that can be deposited is ((5000000000 * 100000000) / (1000000000 - 100000000)) / 0.997 + 1 = 557227238
        //Minimum amount of DAI that can be deposited is ((10000000000 * 557227238) / (1000000000 - 557227238)) / 0.997 + 1 = 12622816890
        //Minimum amount of USDT that can be deposited is ((2000000000 * 12622816890) / (20000000000 - 12622816890)) / 0.997 + 1 = 3432421048
        test_scenario::next_tx(&mut scenario, bob);
        {
            let container = test_scenario::take_shared<Container>(&scenario);
            let usdt = coin::mint_for_testing<USDT>(3432421049, test_scenario::ctx(&mut scenario));
            let amount_usdt_max = 3432421048;
            let amount_btc_out = 100000000;

            router::swap_exact_output_triplehop<USDT, DAI, ETH, BTC>(&clock, &mut container, usdt, amount_usdt_max, 
            amount_btc_out, bob, 99, test_scenario::ctx(&mut scenario));
            let dai_usdt = factory::borrow_pair<DAI, USDT>(&container);
            let (resevse_dai, resevse_usdt) = pair::get_reserves<DAI, USDT>(dai_usdt);
            assert!(resevse_dai == 7377183110 && resevse_usdt == 5432421048, 0);

            let dai_eth = factory::borrow_pair<DAI, ETH>(&container);
            let (resevse_dai, resevse_eth) = pair::get_reserves<DAI, ETH>(dai_eth);
            assert!(resevse_dai == 22622816890 && resevse_eth == 442772762, 0);

            test_scenario::return_shared(container);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let btc = test_scenario::take_from_address<Coin<BTC>>(&scenario, bob);
            assert!(coin::value(&btc) == 100000000, 0);
            let usdt = test_scenario::take_from_address<Coin<USDT>>(&scenario, bob);
            assert!(coin::value(&usdt) == 1, 0);

            test_scenario::return_to_address(bob, btc);
            test_scenario::return_to_address(bob, usdt); 
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}