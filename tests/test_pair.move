#[test_only] 
module swap::test_pair {
    use sui::test_scenario;
    use sui::coin::{Self, Coin};
    use swap::pair::{Self, LP, PairMetadata};
    use swap::swap_utils;
    use swap::treasury;

    struct USDT has drop {}

    struct DAI has drop {}
    const MINIMUM_LIQUIDITY: u64 = 1000;

    #[test]
    fun test_mint() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let treasury = treasury::dummy(@0x0);
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            pair::dummy_pair<USDT, DAI>(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x_amount = 1000000000;
            let coin_y_amount = 4000000000;
            let expected_liquidity = 2000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, coin_y_amount, alice, test_scenario::ctx(&mut scenario));

            assert!(pair::total_lp_supply(&pair) == expected_liquidity, 1);
            let (reserve_x, reserve_y) = pair::get_reserves<USDT, DAI>(&pair);
            assert!(reserve_x == coin_x_amount && reserve_y == coin_y_amount, 3);

            test_scenario::return_shared(pair);
        };

        test_scenario::next_tx(&mut scenario, alice);
        {
            let lp = test_scenario::take_from_sender<Coin<LP<USDT, DAI>>>(&scenario);
            assert!(coin::value(&lp) == (2000000000 - MINIMUM_LIQUIDITY), 0);
            test_scenario::return_to_address<Coin<LP<USDT, DAI>>>(alice, lp);
        };

        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x_amount = 5000000000;
            let coin_y_amount = 40000000000;
            let expected_liquidity = 10000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, coin_y_amount, bob, test_scenario::ctx(&mut scenario));

            assert!(pair::total_lp_supply(&pair) == expected_liquidity + 2000000000, 1);
            let (reserve_x, reserve_y) = pair::get_reserves<USDT, DAI>(&pair);
            assert!(reserve_x == coin_x_amount + 1000000000 && reserve_y == coin_y_amount + 4000000000, 3);
            test_scenario::return_shared(pair);
        };

        test_scenario::next_tx(&mut scenario, alice);
        {
            let lp = test_scenario::take_from_sender<Coin<LP<USDT, DAI>>>(&scenario);
            assert!(coin::value(&lp) == (2000000000 - MINIMUM_LIQUIDITY), 0);
            test_scenario::return_to_sender<Coin<LP<USDT, DAI>>>(&scenario, lp);
        };
        test_scenario::next_tx(&mut scenario, bob);
        {
            let lp = test_scenario::take_from_sender<Coin<LP<USDT, DAI>>>(&scenario);
            assert!(coin::value(&lp) == 10000000000, 0);
            test_scenario::return_to_sender<Coin<LP<USDT, DAI>>>(&scenario, lp);
        };
        
        treasury::destroy_for_testing(treasury);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = pair::ERROR_INSUFFICIENT_LIQUIDITY_MINTED)]
    fun test_mint_fail_if_liquidity_less_than_minimum() {
        let alice = @0xA;
        let scenario = test_scenario::begin(alice);
        let treasury = treasury::dummy(@0x0);

        test_scenario::next_tx(&mut scenario, alice);
        {
            pair::dummy_pair<USDT, DAI>(test_scenario::ctx(&mut scenario));
        };
        
        //At the first time, Alice add liquidity with token_x = 100, token_y=1000; liquidity = sqrt(100*1000) = 1000 <= MINIMUM_LIQUIDITY => throw ERROR_INSUFFICIENT_LIQUIDITY_MINTED
        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x_amount = 100;
            let coin_y_amount = 1000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, coin_y_amount, alice, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pair);
        };

        treasury::destroy_for_testing(treasury);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = pair::ERROR_INSUFFICIENT_LIQUIDITY_MINTED)]
    fun test_mint_fail_if_liquidity_is_zero() {
        let alice = @0xA;
        let scenario = test_scenario::begin(alice);
        let treasury = treasury::dummy(@0x0);

        test_scenario::next_tx(&mut scenario, alice);
        {
            pair::dummy_pair<USDT, DAI>(test_scenario::ctx(&mut scenario));
        };
        
        //At the first time, Alice add liquidity with token_x=1e9, token_y=4e9; liquidity = sqrt(1e9*4e9) - 1000 = 1999999000
        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x_amount = 1000000000;
            let coin_y_amount = 4000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, coin_y_amount, alice, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pair);
        };

        //At the 2nd time, Alice add liquidity with token_x=2e9, token_y=0; liquidity = min(2e9*2e9/1e9, 0*2e9/4e9)=0, should throw ERROR_INSUFFICIENT_LIQUIDITY_MINTED
        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x_amount = 2000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, 0, alice, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pair);
        };

        treasury::destroy_for_testing(treasury);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_burn() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let treasury = treasury::dummy(@0x0);

        test_scenario::next_tx(&mut scenario, alice);
        {
            pair::dummy_pair<USDT, DAI>(test_scenario::ctx(&mut scenario));
        };
        
        //At the first time, Alice add liquidity with token_x=1e9, token_y=4e9; liquidity = sqrt(1e9*4e9) - 1000 = 1999999000
        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x_amount = 1000000000;
            let coin_y_amount = 4000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, coin_y_amount, alice, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pair);
        };

        //At the 2nd time, Bob add liquidity with token_x=5e9, token_y=40e9; liquidity = min(5e9*2e9/1e9, 40*2e9/4e9)=10e9
        test_scenario::next_tx(&mut scenario, bob);
        {
            let coin_x_amount = 5000000000;
            let coin_y_amount = 40000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, coin_y_amount, bob, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pair);
        };

        //Alice remove liquidity, Alice should have: (6e9/12e9)*1999999000=999999500 USDT and (44e9/12e9)*1999999000=7333329666 DAI
        //Liquidity USDT = 6e9-999999500=5000000500, DAI = 44e9-7333329666=36666670334;
        test_scenario::next_tx(&mut scenario, alice);
        {
            let lp = test_scenario::take_from_sender<Coin<LP<USDT, DAI>>>(&scenario);
            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::remove_liquidity<USDT, DAI>(&mut pair, &treasury, lp, alice, test_scenario::ctx(&mut scenario));
            assert!(pair::total_lp_supply(&pair) == 10000001000, 1);
            let (reserve_x, reserve_y) = pair::get_reserves<USDT, DAI>(&pair);
            assert!(reserve_x == 5000000500 && reserve_y == 36666670334, 3);
            test_scenario::return_shared(pair);
        };
        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x = test_scenario::take_from_sender<Coin<USDT>>(&scenario);
            assert!(coin::value(&coin_x) == 999999500, 0);
            test_scenario::return_to_sender<Coin<USDT>>(&scenario, coin_x);
            let coin_y = test_scenario::take_from_sender<Coin<DAI>>(&scenario);
            assert!(coin::value(&coin_y) == 7333329666 , 0);
            test_scenario::return_to_sender<Coin<DAI>>(&scenario, coin_y);
        };

        //Bob remove liquidity, Alice should have: (5000000500/10000001000)*10e9=5000000000 USDT and (36666670334/10000001000)*10e9=36666666667 DAI
        //Liquidity USDT = 5000000500-5000000000=500, DAI = 36666670334-36666666667=3667;
        test_scenario::next_tx(&mut scenario, bob);
        {
            let lp = test_scenario::take_from_sender<Coin<LP<USDT, DAI>>>(&scenario);
            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::remove_liquidity<USDT, DAI>(&mut pair, &treasury, lp, bob, test_scenario::ctx(&mut scenario));
            assert!(pair::total_lp_supply(&pair) == 1000, 1);
            let (reserve_x, reserve_y) = pair::get_reserves<USDT, DAI>(&pair);
            assert!(reserve_x == 500 && reserve_y == 3667, 3);
            test_scenario::return_shared(pair);
        };
        test_scenario::next_tx(&mut scenario, bob);
        {
            let coin_x = test_scenario::take_from_sender<Coin<USDT>>(&scenario);
            assert!(coin::value(&coin_x) == 5000000000, 0);
            test_scenario::return_to_sender<Coin<USDT>>(&scenario, coin_x);
            let coin_y = test_scenario::take_from_sender<Coin<DAI>>(&scenario);
            assert!(coin::value(&coin_y) == 36666666667 , 0);
            test_scenario::return_to_sender<Coin<DAI>>(&scenario, coin_y);
        };
        
        treasury::destroy_for_testing(treasury);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code= pair::ERROR_INSUFFICIENT_LIQUIDITY_BURNED)]
    fun test_burn_fail() {
        let alice = @0xA;
        let scenario = test_scenario::begin(alice);
        let treasury = treasury::dummy(@0x0);

        test_scenario::next_tx(&mut scenario, alice);
        {
            pair::dummy_pair<USDT, DAI>(test_scenario::ctx(&mut scenario));
        };
        
        //At the first time, Alice add liquidity with token_x=1e9, token_y=4e9; liquidity = sqrt(1e9*4e9) - 1000 = 1999999000
        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x_amount = 1000000000;
            let coin_y_amount = 4000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, coin_y_amount, alice, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pair);
        };

        //Alice burn zero lp, should fail, throw ERROR_INSUFFICIENT_LIQUIDITY_BURNED = 1
        test_scenario::next_tx(&mut scenario, alice);
        {
            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::remove_liquidity<USDT, DAI>(&mut pair, &treasury, coin::zero<LP<USDT, DAI>>(test_scenario::ctx(&mut scenario)), alice, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pair);
        };

        treasury::destroy_for_testing(treasury);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let treasury = treasury::dummy(@0x0);

        test_scenario::next_tx(&mut scenario, alice);
        {
            pair::dummy_pair<USDT, DAI>(test_scenario::ctx(&mut scenario));
        };
        
        //At the first time, Alice add liquidity with token_x=100e9, token_y=400e9
        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x_amount = 100000000000;
            let coin_y_amount = 400000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, coin_y_amount, alice, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pair);
        };

        //Bob swap 1 USDT to DAI, Bob should have: (400e9 * 0.997e9)/(100e9+0.997e9)=3948632137 DAI
        //Liquidity USDT = 100e9 + 1e9 = 101e9, DAI = 400e9 - 3948632137 = 396051367863
        test_scenario::next_tx(&mut scenario, bob);
        {
            let amount_x = 1000000000;
            let expected_amount_y = swap_utils::get_amount_out(amount_x, 100000000000, 400000000000);

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::swap_x_to_y<USDT, DAI>(&mut pair, amount_x, expected_amount_y, bob, test_scenario::ctx(&mut scenario));
            let (reserve_x, reserve_y) = pair::get_reserves<USDT, DAI>(&pair);
            assert!(reserve_x == 101000000000 && reserve_y == 396051367863, 0);
            test_scenario::return_shared(pair);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let dai = test_scenario::take_from_sender<Coin<DAI>>(&scenario);
            assert!(coin::value(&dai) == 3948632137, 0);
            test_scenario::return_to_sender<Coin<DAI>>(&scenario, dai);
        };

        //Bob swap 2 DAI to USDT, Bob should have: (101000000000 * 1.994e9)/(396051367863+1.994e9)=505957401 USDT
        //Liquidity USDT = 101e9 - 505957401 = 100494042599, DAI = 396051367863 + 2e9 = 398051367863
        test_scenario::next_tx(&mut scenario, bob);
        {
            let amount_y = 2000000000;
            let expected_amount_x = swap_utils::get_amount_out(amount_y, 396051367863, 101000000000);

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::swap_y_to_x<USDT, DAI>(&mut pair, amount_y, expected_amount_x, bob, test_scenario::ctx(&mut scenario));
            let (reserve_x, reserve_y) = pair::get_reserves<USDT, DAI>(&pair);
            assert!(reserve_x == 100494042599 && reserve_y == 398051367863, 0);
            test_scenario::return_shared(pair);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let dai = test_scenario::take_from_sender<Coin<DAI>>(&scenario);
            assert!(coin::value(&dai) == 3948632137, 0);
            test_scenario::return_to_sender<Coin<DAI>>(&scenario, dai);

            let usdt = test_scenario::take_from_sender<Coin<USDT>>(&scenario);
            assert!(coin::value(&usdt) == 505957401, 0);
            test_scenario::return_to_sender<Coin<USDT>>(&scenario, usdt);
        };

        treasury::destroy_for_testing(treasury);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = pair::ERROR_K)]
    fun test_swap_fail() {
        let alice = @0xA;
        let bob = @0xB;
        let scenario = test_scenario::begin(alice);
        let treasury = treasury::dummy(@0x0);

        test_scenario::next_tx(&mut scenario, alice);
        {
            pair::dummy_pair<USDT, DAI>(test_scenario::ctx(&mut scenario));
        };
        
        //At the first time, Alice add liquidity with token_x=100e9, token_y=400e9
        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x_amount = 100000000000;
            let coin_y_amount = 400000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, coin_y_amount, alice, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pair);
        };

        //Bob swap 1 USDT to DAI and expect to get 5 DAI, should fail, throw ERROR_K = 5
        test_scenario::next_tx(&mut scenario, bob);
        {
            let amount_x = 1000000000;
            let expected_amount_y = 5000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::swap_x_to_y<USDT, DAI>(&mut pair, amount_x, expected_amount_y, bob, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pair);
        };
        
        treasury::destroy_for_testing(treasury);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_protocol_fee() {
        let alice = @0xA;
        let bob = @0xB;
        let treasurer = @0xc;
        let scenario = test_scenario::begin(alice);
        let treasury = treasury::dummy(treasurer);
        let total_fee = 0;
        
        test_scenario::next_tx(&mut scenario, alice);
        {
            pair::dummy_pair<USDT, DAI>(test_scenario::ctx(&mut scenario));
        };
        
        //At the first time, Alice add liquidity with token_x=100e9, token_y=400e9
        //reserve_x = 100000000000, reserve_y=400000000000, lp_supply=200000000000
        //protocol_fee = 0
        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x_amount = 100000000000;
            let coin_y_amount = 400000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, coin_y_amount, alice, test_scenario::ctx(&mut scenario));
            assert!(pair::total_lp_supply(&pair) == 200000000000, 1);
            let (reserve_x, reserve_y) = pair::get_reserves<USDT, DAI>(&pair);
            assert!(reserve_x == 100000000000 && reserve_y == 400000000000, 3);
            test_scenario::return_shared(pair);
        };
        test_scenario::next_tx(&mut scenario, alice);
        {
            assert!(!test_scenario::has_most_recent_for_address<Coin<LP<DAI, USDT>>>(treasurer), 0);
        };

        //Bob swap 1 USDT to DAI
        //reserve_x = 101e9, reserve_y=396051367863, lp_supply=200000000000
        //protocol_fee = 0
        test_scenario::next_tx(&mut scenario, bob);
        {
            let amount_x = 1000000000;
            let expected_amount_y = swap_utils::get_amount_out(amount_x, 100000000000, 400000000000);

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::swap_x_to_y<USDT, DAI>(&mut pair, amount_x, expected_amount_y, bob, test_scenario::ctx(&mut scenario));
            assert!(pair::total_lp_supply(&pair) == 200000000000, 1);
            let (reserve_x, reserve_y) = pair::get_reserves<USDT, DAI>(&pair);
            assert!(reserve_x == 101000000000 && reserve_y == 396051367863, 3);
            test_scenario::return_shared(pair);
        };
        test_scenario::next_tx(&mut scenario, alice);
        {
            assert!(!test_scenario::has_most_recent_for_address<Coin<LP<USDT, DAI>>>(treasurer), 0);
        };

        
        //Bob swap 2 DAI to USDT
        //reserve_x = 100494042599, reserve_y=398051367863, lp_supply=200000000000
        //protocol_fee = 0
        test_scenario::next_tx(&mut scenario, bob);
        {
            let amount_y = 2000000000;
            let expected_amount_x = swap_utils::get_amount_out(amount_y, 396051367863, 101000000000);

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::swap_y_to_x<USDT, DAI>(&mut pair, amount_y, expected_amount_x, bob, test_scenario::ctx(&mut scenario));
            assert!(pair::total_lp_supply(&pair) == 200000000000, 1);
            let (reserve_x, reserve_y) = pair::get_reserves<USDT, DAI>(&pair);
            assert!(reserve_x == 100494042599 && reserve_y == 398051367863, 3);
            test_scenario::return_shared(pair);
        };
        test_scenario::next_tx(&mut scenario, alice);
        {
            assert!(!test_scenario::has_most_recent_for_address<Coin<LP<USDT, DAI>>>(treasurer), 0);
        };

        //Alice add liquidity, lp_supply=200000000000
        //root_k = sqrt(100494042599 * 398051367863) = 200004477746;
        //root_k_last = sqrt(4e22) = 200000000000
        //protocol_fee = (lp_supply * (rook_k - root_k_last)) / (5 * root_k + root_k_last) = 746277
        //lp_supply = min(200000000000 * (200000746277/100494042599), 800000000000 * (200000746277/398051367863)) + 200000746277 = 598035776224
        //k = 300494042599 * 1198051367863 = 3.600072987704145e23
        test_scenario::next_tx(&mut scenario, alice);
        {
            let coin_x_amount = 200000000000;
            let coin_y_amount = 800000000000;

            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::add_liquidity<USDT, DAI>(&mut pair, &treasury, coin_x_amount, coin_y_amount, alice, test_scenario::ctx(&mut scenario));
            assert!(pair::total_lp_supply(&pair) == 598035776224, 0);
            test_scenario::return_shared(pair);
        };
        test_scenario::next_tx(&mut scenario, alice);
        {
            let fee = test_scenario::take_from_address<Coin<LP<USDT, DAI>>>(&scenario, treasurer);
            total_fee = total_fee + coin::value(&fee);
            assert!(total_fee == 746277, 0);
            test_scenario::return_to_address(treasurer, fee);
        };

        //Bob swap 10 USDT to DAI
        //reserve_x = 310494042599, reserve_y = 1159578081110, lp_supply=598035776224
        //protocol_fee = 0
        test_scenario::next_tx(&mut scenario, bob);
        {
            let amount_x = 10000000000;
            let expected_amount_y = swap_utils::get_amount_out(amount_x, 300494042599, 1198051367863);
            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::swap_x_to_y<USDT, DAI>(&mut pair, amount_x, expected_amount_y, bob, test_scenario::ctx(&mut scenario));
            assert!(pair::total_lp_supply(&pair) == 598035776224, 1);
            let (reserve_x, reserve_y) = pair::get_reserves<USDT, DAI>(&pair);
            assert!(reserve_x == 310494042599 && reserve_y == 1159578081110, 1);
            test_scenario::return_shared(pair);
        };
        test_scenario::next_tx(&mut scenario, alice);
        {
            let fee = test_scenario::take_from_address<Coin<LP<USDT, DAI>>>(&scenario, treasurer);
            assert!(coin::value(&fee) == 746277, 0);
            test_scenario::return_to_address(treasurer, fee);
        };

        //Alice remove liquidity, lp_supply=598035776224
        //root_k = sqrt(310494042599 * 1159578081110) = 600035070735;
        //root_k_last = sqrt(3.600072987704145e23) = 600006082277
        //protocol_fee = 746277 + (lp_supply * (rook_k - root_k_last)) / (5 * root_k + root_k_last) = (598035776224 * (600035070735 - 600006082277)) / (5 * 600035070735 + 600006082277) = 5561627
        test_scenario::next_tx(&mut scenario, alice);
        {
            let lp = test_scenario::take_from_sender<Coin<LP<USDT, DAI>>>(&scenario);
            let pair = test_scenario::take_shared<PairMetadata<USDT, DAI>>(&scenario);
            pair::remove_liquidity<USDT, DAI>(&mut pair, &treasury, lp, alice, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pair);
        };
        test_scenario::next_tx(&mut scenario, alice);
        {
            let fee = test_scenario::take_from_address<Coin<LP<USDT, DAI>>>(&scenario, treasurer);
            total_fee = total_fee + coin::value(&fee);
            assert!(total_fee == 5561627, 0);
            test_scenario::return_to_address(treasurer, fee);
        };
        treasury::destroy_for_testing(treasury);
        test_scenario::end(scenario);
    }
}