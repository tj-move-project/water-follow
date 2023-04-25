/// Uniswap v2 router like program
module swap::router {
    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::clock::{Self, Clock};

    use swap::pair::{Self, LP, PairMetadata};
    use swap::factory::{Self, Container};
    use swap::treasury::Treasury;
    use swap::swap_utils;

    const ERROR_INSUFFICIENT_X_AMOUNT: u64 = 0;
    const ERROR_INSUFFICIENT_Y_AMOUNT: u64 = 1;
    const ERROR_INVALID_AMOUNT: u64 = 3;
    const ERROR_EXPIRED: u64 = 4;
    const ERROR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 5;
    const ERROR_EXCESSIVE_INPUT_AMOUNT: u64 = 6;

    fun ensure(clock: &Clock, deadline: u64) {
        assert!(deadline >= clock::timestamp_ms(clock), ERROR_EXPIRED);
    }

    public fun add_liquidity_direct<X, Y>(
        pair: &mut PairMetadata<X, Y>,
        treasury: &Treasury,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        amount_x_min: u64,
        amount_y_min: u64,
        ctx: &mut TxContext
        ): Coin<LP<X, Y>> {
        let (amount_x_desired, amount_y_desired) = (coin::value<X>(&coin_x), coin::value<Y>(&coin_y));
        let (reserve_x, reserve_y) = pair::get_reserves<X, Y>(pair);
        let (amount_x, amount_y) = if (reserve_x == 0 && reserve_y == 0) {
            (amount_x_desired, amount_y_desired)
        } else {
            let amount_y_optimal = swap_utils::quote(amount_x_desired, reserve_x, reserve_y);
            if(amount_y_optimal <= amount_y_desired) {
                assert!(amount_y_optimal >= amount_y_min, ERROR_INSUFFICIENT_Y_AMOUNT);
                (amount_x_desired, amount_y_optimal)
            } else {
                let amount_x_optimal = swap_utils::quote(amount_y_desired, reserve_y, reserve_x);
                assert!(amount_x_optimal <= amount_x_desired, ERROR_INVALID_AMOUNT);
                assert!(amount_x_optimal >= amount_x_min, ERROR_INSUFFICIENT_X_AMOUNT);
                (amount_x_optimal, amount_y_desired)
            }
        };

        let sender_addr = tx_context::sender(ctx);
        if (amount_x_desired > amount_x) {
            let left_x = coin::split<X>(&mut coin_x, amount_x_desired - amount_x, ctx);
            transfer::public_transfer(left_x, sender_addr);
        };
        if (amount_y_desired > amount_y) {
            let left_y = coin::split<Y>(&mut coin_y, amount_y_desired - amount_y, ctx);
            transfer::public_transfer(left_y, sender_addr);
        };

        pair::mint<X, Y>(pair, treasury, coin_x, coin_y, ctx)
    }
    
    /// Add liquidity for two coins X and Y.
    /// A liquidity pool will be created if it does not exist yet.
    ///  * `container` - the container that holds all of AMM's liquidity pools.
    ///  * `vec_coin_x` - list of coins X offered to pay for adding liquidity.
    ///  * `vec_coin_y` - list of coins Y offered to pay for adding liquidity.
    ///  * `amount_x_desired` - desired amount of coin X to add as liquidity.
    ///  * `amount_y_desired` - desired amount of coin Y to add as liquidity.
    ///  * `amount_x_min` - minimum amount of coin X to add as liquidity.
    ///  * `amount_y_min` - minimum amount of coin Y to add as liquidity.
    ///  * `to` - address to receive LP coin.
    ///  * `deadline` - deadline of the transaction.
    public entry fun add_liquidity<X, Y>(
        clock: &Clock,
        container: &mut Container,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        amount_x_min: u64,
        amount_y_min: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext
    ) {
        ensure(clock, deadline);
        if (!factory::pair_is_created<X, Y>(container)) {
            factory::create_pair<X, Y>(container, ctx);
        };

        if (swap_utils::is_ordered<X, Y>()) {
            let (pair, treasury) = factory::borrow_mut_pair_and_treasury<X, Y>(container);
            let lp_coin = add_liquidity_direct<X, Y>(pair, treasury, coin_x, coin_y, amount_x_min, amount_y_min, ctx);
            transfer::public_transfer(lp_coin, to);
        } else {
            let (pair, treasury) = factory::borrow_mut_pair_and_treasury<Y, X>(container);
            let lp_coin = add_liquidity_direct<Y, X>(pair, treasury, coin_y, coin_x, amount_y_min, amount_x_min, ctx);
            transfer::public_transfer(lp_coin, to);
        };
    }

    /// Remove the liquidity of two coins X and Y.
    ///  * `container` - the container that holds all of AMM's liquidity pools.
    ///  * `lp_coin` - list of coins LP offered to pay for removing liquidity.
    ///  * `amount_lp_desired` - desired amount of coin LP to remove as liquidity.
    ///  * `amount_x_min` - minimum amount of coin X will be received.
    ///  * `amount_y_min` - minimum amount of coin Y will be received.
    ///  * `to` - address to receive coin X and coin Y.
    ///  * `deadline` - deadline of the transaction.
    public entry fun remove_liquidity<X, Y>(
        clock: &Clock,
        container: &mut Container,
        lp_coin: Coin<LP<X, Y>>,
        amount_x_min: u64,
        amount_y_min: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext
    ) {
        ensure(clock, deadline);
        let (pair, treasury) = factory::borrow_mut_pair_and_treasury<X, Y>(container);
        let (coin_x_out, coin_y_out) = pair::burn(pair, treasury, lp_coin, ctx);
        let (amount_x_out, amount_y_out) = (coin::value<X>(&coin_x_out), coin::value<Y>(&coin_y_out));
        assert!(amount_x_out >= amount_x_min, ERROR_INSUFFICIENT_X_AMOUNT);
        assert!(amount_y_out >= amount_y_min, ERROR_INSUFFICIENT_Y_AMOUNT);

        transfer::public_transfer(coin_x_out, to);
        transfer::public_transfer(coin_y_out, to);
    }

    /// Swap exact coin `X` for coin `Y`.
    public fun swap_exact_x_to_y_direct<X, Y>(
        pair: &mut PairMetadata<X, Y>,
        coin_x_in: Coin<X>,
        ctx: &mut TxContext
    ): Coin<Y> {
        let amount_x_in = coin::value<X>(&coin_x_in);
        let (reserve_in, reserve_out) = pair::get_reserves(pair);
        let amount_y_out = swap_utils::get_amount_out(amount_x_in, reserve_in, reserve_out);
        let (coin_x_out, coin_y_out) = pair::swap<X, Y>(pair, coin_x_in, 0, coin::zero<Y>(ctx), amount_y_out, ctx);
        assert!(coin::value<X>(&coin_x_out) == 0 && coin::value<Y>(&coin_y_out) > 0, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        coin::destroy_zero<X>(coin_x_out);
        coin_y_out
    }

    /// Swap exact coin `Y` for coin `X`.
    public fun swap_exact_y_to_x_direct<X, Y>(
        pair: &mut PairMetadata<X, Y>,
        coin_y_in: Coin<Y>,
        ctx: &mut TxContext
    ): Coin<X> {
        let amount_y_in = coin::value<Y>(&coin_y_in);
        let (reserve_out, reserve_in) = pair::get_reserves<X, Y>(pair);
        let amount_x_out = swap_utils::get_amount_out(amount_y_in, reserve_in, reserve_out);
        let (coin_x_out, coin_y_out) = pair::swap<X, Y>(pair, coin::zero<X>(ctx), amount_x_out, coin_y_in, 0, ctx);
        assert!(coin::value<Y>(&coin_y_out) == 0 && coin::value<X>(&coin_x_out) > 0, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        coin::destroy_zero<Y>(coin_y_out);
        coin_x_out
    }

    public fun swap_exact_input_direct<X, Y>(
        container: &mut Container,
        coin_x_in: Coin<X>,
        ctx: &mut TxContext
    ): Coin<Y> {
        let coin_y_out = if (swap_utils::is_ordered<X, Y>()) {
            let pair = factory::borrow_mut_pair<X, Y>(container);
            swap_exact_x_to_y_direct<X, Y>(pair, coin_x_in, ctx)
        } else {
            let pair = factory::borrow_mut_pair<Y, X>(container);
            swap_exact_y_to_x_direct<Y, X>(pair, coin_x_in, ctx)
        };

        coin_y_out
    }

    /// Swap exact coin `X` for coin `Y`.
    ///  * `container` - the container that holds all of AMM's liquidity pools.
    ///  * `vec_coin_x_in` - list of coins X offered for swap.
    ///  * `amount_x_desired` - desired amount of coin X to swap.
    ///  * `amount_y_min_out` - minimum amount of coin X will be received.
    ///  * `to` - address to receive coin X and coin Y.
    ///  * `deadline` - deadline of the transaction.
    public entry fun swap_exact_input<X, Y>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        amount_y_min_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext
    ) {
        ensure(clock, deadline);
        let coin_y_out = swap_exact_input_direct<X, Y>(container, coin_x_in, ctx);
        assert!(coin::value<Y>(&coin_y_out) >= amount_y_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_y_out, to);
    }

    ///  Swap exact coin `X` for coin `Z`.
    ///  * `container` - the container that holds all of AMM's liquidity pools.
    ///  * `vec_coin_x_in` - list of coins X offered for swap.
    ///  * `amount_x_desired` - desired amount of coin X to swap.
    ///  * `amount_z_min_out` - minimum amount coin Z will be received.
    ///  * `to` - address to receive coin Z.
    ///  * `deadline` - deadline of the transaction.
    public entry fun swap_exact_input_doublehop<X, Y, Z>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        amount_z_min_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext
    ) {
        ensure(clock, deadline);
        let coin_y_out = swap_exact_input_direct<X, Y>(container, coin_x_in, ctx);
        let coin_z_out = swap_exact_input_direct<Y, Z>(container, coin_y_out, ctx);
        assert!(coin::value<Z>(&coin_z_out) >= amount_z_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_z_out, to);
    }

    ///  Swap exact coin `X` for coin `W`.
    ///  * `container` - the container that holds all of AMM's liquidity pools.
    ///  * `vec_coin_x_in` - list of coins X offered for swap.
    ///  * `amount_x_desired` - desired amount of coin X to swap.
    ///  * `amount_w_min_out` - minimum amount coin W will be received.
    ///  * `to` - address to receive coin W.
    ///  * `deadline` - deadline of the transaction.
    public entry fun swap_exact_input_triplehop<X, Y, Z, W>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        amount_w_min_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext
    ) {
        ensure(clock, deadline);
        let coin_y_out = swap_exact_input_direct<X, Y>(container, coin_x_in, ctx);
        let coin_z_out = swap_exact_input_direct<Y, Z>(container, coin_y_out, ctx);
        let coin_w_out = swap_exact_input_direct<Z, W>(container, coin_z_out, ctx);
        assert!(coin::value<W>(&coin_w_out) >= amount_w_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_w_out, to);
    }

    public fun swap_x_to_exact_y_direct<X, Y>(
        pair: &mut PairMetadata<X, Y>,
        coin_x_in: Coin<X>,
        amount_y_out: u64,
        ctx: &mut TxContext
    ): Coin<Y> {
        let amount_x_in = coin::value<X>(&coin_x_in);
        let (reserve_in, reserve_out) = pair::get_reserves<X, Y>(pair);
        let amount_x_required = swap_utils::get_amount_in(amount_y_out, reserve_in, reserve_out);
        assert!(amount_x_required <= amount_x_in, ERROR_EXCESSIVE_INPUT_AMOUNT);

        //Return change to sender
        if (amount_x_in > amount_x_required) {
            let sender_addr = tx_context::sender(ctx);
            transfer::public_transfer<Coin<X>>(coin::split<X>(&mut coin_x_in, amount_x_in - amount_x_required, ctx), sender_addr);
        };
        
        let (coin_x_out, coin_y_out) = pair::swap<X, Y>(pair, coin_x_in, 0, coin::zero<Y>(ctx), amount_y_out, ctx);
        assert!(coin::value<X>(&coin_x_out) == 0 && coin::value<Y>(&coin_y_out) > 0, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        coin::destroy_zero<X>(coin_x_out);
        coin_y_out
    }

    public fun swap_y_to_exact_x_direct<X, Y>(
        pair: &mut PairMetadata<X, Y>,
        coin_y_in: Coin<Y>,
        amount_x_out: u64,
        ctx: &mut TxContext
    ): Coin<X> {
        let amount_y_in = coin::value<Y>(&coin_y_in);
        let (reserve_out, reserve_in) = pair::get_reserves<X, Y>(pair);
        let amount_y_required = swap_utils::get_amount_in(amount_x_out, reserve_in, reserve_out);
        assert!(amount_y_required <= amount_y_in, ERROR_EXCESSIVE_INPUT_AMOUNT);
        //Return change to sender
        if (amount_y_in > amount_y_required) {
            let sender_addr = tx_context::sender(ctx);
            transfer::public_transfer<Coin<Y>>(coin::split<Y>(&mut coin_y_in, amount_y_in - amount_y_required, ctx), sender_addr);
        };

        let (coin_x_out, coin_y_out) = pair::swap<X, Y>(pair, coin::zero<X>(ctx), amount_x_out, coin_y_in, 0, ctx);
        assert!(coin::value<Y>(&coin_y_out) == 0 && coin::value<X>(&coin_x_out) > 0, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        coin::destroy_zero<Y>(coin_y_out);
        coin_x_out
    }

    public fun swap_exact_output_direct<X, Y>(
        container: &mut Container,
        coin_x_in: Coin<X>,
        amount_y_out: u64,
        ctx: &mut TxContext
    ): Coin<Y> {
        let coin_y_out = if (swap_utils::is_ordered<X, Y>()) {
            let pair = factory::borrow_mut_pair<X, Y>(container);
            swap_x_to_exact_y_direct<X, Y>(pair, coin_x_in, amount_y_out, ctx)
        } else {
            let pair = factory::borrow_mut_pair<Y, X>(container);
            swap_y_to_exact_x_direct<Y, X>(pair, coin_x_in, amount_y_out, ctx)
        };
        coin_y_out
    }

    ///  Swap coin `X` for exact coin `Y`.
    ///  * `container` - the container that holds all of AMM's liquidity pools.
    ///  * `vec_coin_x_in` - list of coins X offered for swap.
    ///  * `amount_x_max` - maximum amount of coin X to swap.
    ///  * `amount_y_out` - exact amount coin X will be received.
    ///  * `to` - address to receive coin X.
    ///  * `deadline` - deadline of the transaction.
    public entry fun swap_exact_output<X, Y>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        amount_x_max: u64,
        amount_y_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext
    ) {
        ensure(clock, deadline);
        let left_amount = swap_utils::left_amount(&coin_x_in, amount_x_max);
        if (left_amount > 0) {
            let left_x = coin::split(&mut coin_x_in, left_amount, ctx);
            //Give left-x
            transfer::public_transfer(left_x, tx_context::sender(ctx));
        };
        let coin_y_out = swap_exact_output_direct<X, Y>(container, coin_x_in, amount_y_out, ctx);
        transfer::public_transfer(coin_y_out, to);
    }

    ///  Swap coin `X` for exact coin `Z`.
    ///  * `container` - the container that holds all of AMM's liquidity pools.
    ///  * `vec_coin_x_in` - list of coins X offered for swap.
    ///  * `amount_x_max` - maximum amount of coin X to swap.
    ///  * `amount_z_out` - exact amount coin Z will be received.
    ///  * `to` - address to receive coin Z.
    ///  * `deadline` - deadline of the transaction.
    public entry fun swap_exact_output_doublehop<X, Y, Z>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        amount_x_max: u64,
        amount_z_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext
    ) {
        ensure(clock, deadline);
        let amount_y_required = if (swap_utils::is_ordered<Y, Z>()) {
            let pair = factory::borrow_pair<Y, Z>(container);
            let (reserve_in, reserve_out) = pair::get_reserves<Y, Z>(pair);
            swap_utils::get_amount_in(amount_z_out, reserve_in, reserve_out)
        } else {
            let pair = factory::borrow_pair<Z, Y>(container);
            let (reserve_out, reserve_in) = pair::get_reserves<Z, Y>(pair);
            swap_utils::get_amount_in(amount_z_out, reserve_in, reserve_out)
        };

        let left_amount = swap_utils::left_amount(&coin_x_in, amount_x_max);
        if (left_amount > 0) {
            let left_x = coin::split(&mut coin_x_in, left_amount, ctx);
            //Give left-x
            transfer::public_transfer(left_x, tx_context::sender(ctx));
        };
        let coin_y_out = swap_exact_output_direct<X, Y>(container, coin_x_in, amount_y_required, ctx);
        let coin_z_out = swap_exact_output_direct<Y, Z>(container, coin_y_out, amount_z_out, ctx);
        transfer::public_transfer(coin_z_out, to);
    }

    ///  Swap coin `X` for exact coin `W`.
    ///  * `container` - the container that holds all of AMM's liquidity pools.
    ///  * `vec_coin_x_in` - list of coins X offered for swap.
    ///  * `amount_x_max` - maximum amount of coin X to swap.
    ///  * `amount_w_out` - exact amount coin W will be received.
    ///  * `to` - address to receive coin W.
    ///  * `deadline` - deadline of the transaction.
    public entry fun swap_exact_output_triplehop<X, Y, Z, W>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        amount_x_max: u64,
        amount_w_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext
    ) {
        ensure(clock, deadline);
        let amount_z_required = if (swap_utils::is_ordered<Z, W>()) {
            let pair = factory::borrow_pair<Z, W>(container);
            let (reserve_in, reserve_out) = pair::get_reserves<Z, W>(pair);
            swap_utils::get_amount_in(amount_w_out, reserve_in, reserve_out)
        } else {
            let pair = factory::borrow_pair<W, Z>(container);
            let (reserve_out, reserve_in) = pair::get_reserves<W, Z>(pair);
            swap_utils::get_amount_in(amount_w_out, reserve_in, reserve_out)
        };
        let amount_y_required = if (swap_utils::is_ordered<Y, Z>()) {
            let pair = factory::borrow_pair<Y, Z>(container);
            let (reserve_in, reserve_out) = pair::get_reserves<Y, Z>(pair);
            swap_utils::get_amount_in(amount_z_required, reserve_in, reserve_out)
        } else {
            let pair = factory::borrow_pair<Z, Y>(container);
            let (reserve_out, reserve_in) = pair::get_reserves<Z, Y>(pair);
            swap_utils::get_amount_in(amount_z_required, reserve_in, reserve_out)
        };
        let left_amount = swap_utils::left_amount(&coin_x_in, amount_x_max);
        if (left_amount > 0) {
            let left_x = coin::split(&mut coin_x_in, left_amount, ctx);
            //Give left-x
            transfer::public_transfer(left_x, tx_context::sender(ctx));
        };
        let coin_y_out = swap_exact_output_direct<X, Y>(container, coin_x_in, amount_y_required, ctx);
        let coin_z_out = swap_exact_output_direct<Y, Z>(container, coin_y_out, amount_z_required, ctx);
        let coin_w_out = swap_exact_output_direct<Z, W>(container, coin_z_out, amount_w_out, ctx);
        transfer::public_transfer(coin_w_out, to);
    }

    public entry fun swap_exact_input_double_output<X, Y, Z>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        amount_x_to_y_desired: u64,
        amount_x_to_z_desired: u64,
        amount_y_min_out: u64,
        amount_z_min_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext,
    ) {
        ensure(clock, deadline);
        let coin_x_to_y_desired = coin::split(&mut coin_x_in, amount_x_to_y_desired, ctx);
        let coin_x_to_z_desired = coin::split(&mut coin_x_in, amount_x_to_z_desired, ctx);
        //Give change
        transfer::public_transfer(coin_x_in, tx_context::sender(ctx));

        let coin_y_out = swap_exact_input_direct<X, Y>(container, coin_x_to_y_desired, ctx);
        assert!(coin::value<Y>(&coin_y_out) >= amount_y_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_y_out, to);
        let coin_z_out = swap_exact_input_direct<X, Z>(container, coin_x_to_z_desired, ctx);
        assert!(coin::value<Z>(&coin_z_out) >= amount_z_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_z_out, to);
    }

    public entry fun swap_exact_input_triple_output<X, Y, Z, W>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        amount_x_to_y_desired: u64,
        amount_x_to_z_desired: u64,
        amount_x_to_w_desired: u64,
        amount_y_min_out: u64,
        amount_z_min_out: u64,
        amount_w_min_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext,
    ) {
        ensure(clock, deadline);
        let coin_x_to_y_desired = coin::split(&mut coin_x_in, amount_x_to_y_desired, ctx);
        let coin_x_to_z_desired = coin::split(&mut coin_x_in, amount_x_to_z_desired, ctx);
        let coin_x_to_w_desired = coin::split(&mut coin_x_in, amount_x_to_w_desired, ctx);
        //Give change
        transfer::public_transfer(coin_x_in, tx_context::sender(ctx));

        let coin_y_out = swap_exact_input_direct<X, Y>(container, coin_x_to_y_desired, ctx);
        assert!(coin::value<Y>(&coin_y_out) >= amount_y_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_y_out, to);
        let coin_z_out = swap_exact_input_direct<X, Z>(container, coin_x_to_z_desired, ctx);
        assert!(coin::value<Z>(&coin_z_out) >= amount_z_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_z_out, to);
        let coin_w_out = swap_exact_input_direct<X, W>(container, coin_x_to_w_desired, ctx);
        assert!(coin::value<W>(&coin_w_out) >= amount_w_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_w_out, to);
    }

    public entry fun swap_exact_input_quadruple_output<X, Y, Z, W, V>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        amount_x_to_y_desired: u64,
        amount_x_to_z_desired: u64,
        amount_x_to_w_desired: u64,
        amount_x_to_v_desired: u64,
        amount_y_min_out: u64,
        amount_z_min_out: u64,
        amount_w_min_out: u64,
        amount_v_min_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext,
    ) {
        ensure(clock, deadline);
        let coin_x_to_y_desired = coin::split(&mut coin_x_in, amount_x_to_y_desired, ctx);
        let coin_x_to_z_desired = coin::split(&mut coin_x_in, amount_x_to_z_desired, ctx);
        let coin_x_to_w_desired = coin::split(&mut coin_x_in, amount_x_to_w_desired, ctx);
        let coin_x_to_v_desired = coin::split(&mut coin_x_in, amount_x_to_v_desired, ctx);
        //Give change
        transfer::public_transfer(coin_x_in, tx_context::sender(ctx));

        let coin_y_out = swap_exact_input_direct<X, Y>(container, coin_x_to_y_desired, ctx);
        assert!(coin::value<Y>(&coin_y_out) >= amount_y_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_y_out, to);
        let coin_z_out = swap_exact_input_direct<X, Z>(container, coin_x_to_z_desired, ctx);
        assert!(coin::value<Z>(&coin_z_out) >= amount_z_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_z_out, to);
        let coin_w_out = swap_exact_input_direct<X, W>(container, coin_x_to_w_desired, ctx);
        assert!(coin::value<W>(&coin_w_out) >= amount_w_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_w_out, to);
        let coin_v_out = swap_exact_input_direct<X, V>(container, coin_x_to_v_desired, ctx);
        assert!(coin::value<V>(&coin_v_out) >= amount_v_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_v_out, to);
    }

    public entry fun swap_exact_input_quintuple_output<X, Y, Z, W, V, U>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        amount_x_to_y_desired: u64,
        amount_x_to_z_desired: u64,
        amount_x_to_w_desired: u64,
        amount_x_to_v_desired: u64,
        amount_x_to_u_desired: u64,
        amount_y_min_out: u64,
        amount_z_min_out: u64,
        amount_w_min_out: u64,
        amount_v_min_out: u64,
        amount_u_min_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext,
    ) {
        ensure(clock, deadline);
        let coin_x_to_y_desired = coin::split(&mut coin_x_in, amount_x_to_y_desired, ctx);
        let coin_x_to_z_desired = coin::split(&mut coin_x_in, amount_x_to_z_desired, ctx);
        let coin_x_to_w_desired = coin::split(&mut coin_x_in, amount_x_to_w_desired, ctx);
        let coin_x_to_v_desired = coin::split(&mut coin_x_in, amount_x_to_v_desired, ctx);
        let coin_x_to_u_desired = coin::split(&mut coin_x_in, amount_x_to_u_desired, ctx);
        //Give change
        transfer::public_transfer(coin_x_in, tx_context::sender(ctx));

        let coin_y_out = swap_exact_input_direct<X, Y>(container, coin_x_to_y_desired, ctx);
        assert!(coin::value<Y>(&coin_y_out) >= amount_y_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_y_out, to);
        let coin_z_out = swap_exact_input_direct<X, Z>(container, coin_x_to_z_desired, ctx);
        assert!(coin::value<Z>(&coin_z_out) >= amount_z_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_z_out, to);
        let coin_w_out = swap_exact_input_direct<X, W>(container, coin_x_to_w_desired, ctx);
        assert!(coin::value<W>(&coin_w_out) >= amount_w_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_w_out, to);
        let coin_v_out = swap_exact_input_direct<X, V>(container, coin_x_to_v_desired, ctx);
        assert!(coin::value<V>(&coin_v_out) >= amount_v_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_v_out, to);
        let coin_u_out = swap_exact_input_direct<X, U>(container, coin_x_to_u_desired, ctx);
        assert!(coin::value<U>(&coin_u_out) >= amount_u_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_u_out, to);
    }

    public entry fun swap_exact_double_input<X, Y, Z>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        coin_y_in: Coin<Y>,
        amount_z_min_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext,
    ) {
        ensure(clock, deadline);
        let coin_z_out = swap_exact_input_direct<X, Z>(container, coin_x_in, ctx);
        coin::join<Z>(&mut coin_z_out, swap_exact_input_direct<Y, Z>(container, coin_y_in, ctx));
        assert!(coin::value<Z>(&coin_z_out) >= amount_z_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_z_out, to);
    }

    public entry fun swap_exact_triple_input<X, Y, Z, W>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        coin_y_in: Coin<Y>,
        coin_z_in: Coin<Z>,
        amount_w_min_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext,
    ) {
        ensure(clock, deadline);
        let coin_w_out = swap_exact_input_direct<X, W>(container, coin_x_in, ctx);
        coin::join<W>(&mut coin_w_out, swap_exact_input_direct<Y, W>(container, coin_y_in, ctx));
        coin::join<W>(&mut coin_w_out, swap_exact_input_direct<Z, W>(container, coin_z_in, ctx));
        assert!(coin::value<W>(&coin_w_out) >= amount_w_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_w_out, to);
    }

    public entry fun swap_exact_quadruple_input<X, Y, Z, W, V>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        coin_y_in: Coin<Y>,
        coin_z_in: Coin<Z>,
        coin_w_in: Coin<W>,
        amount_v_min_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext,
    ) {
        ensure(clock, deadline);
        let coin_v_out = swap_exact_input_direct<X, V>(container, coin_x_in, ctx);
        coin::join<V>(&mut coin_v_out, swap_exact_input_direct<Y, V>(container, coin_y_in, ctx));
        coin::join<V>(&mut coin_v_out, swap_exact_input_direct<Z, V>(container, coin_z_in, ctx));
        coin::join<V>(&mut coin_v_out, swap_exact_input_direct<W, V>(container, coin_w_in, ctx));
        assert!(coin::value<V>(&coin_v_out) >= amount_v_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_v_out, to);
    }

    public entry fun swap_exact_quintuple_input<X, Y, Z, W, V, U>(
        clock: &Clock,
        container: &mut Container,
        coin_x_in: Coin<X>,
        coin_y_in: Coin<Y>,
        coin_z_in: Coin<Z>,
        coin_w_in: Coin<W>,
        coin_v_in: Coin<V>,
        amount_u_min_out: u64,
        to: address,
        deadline: u64,
        ctx: &mut TxContext,
    ) {
        ensure(clock, deadline);
        let coin_u_out = swap_exact_input_direct<X, U>(container, coin_x_in, ctx);
        coin::join<U>(&mut coin_u_out, swap_exact_input_direct<Y, U>(container, coin_y_in, ctx));
        coin::join<U>(&mut coin_u_out, swap_exact_input_direct<Z, U>(container, coin_z_in, ctx));
        coin::join<U>(&mut coin_u_out, swap_exact_input_direct<W, U>(container, coin_w_in, ctx));
        coin::join<U>(&mut coin_u_out, swap_exact_input_direct<V, U>(container, coin_v_in, ctx));
        assert!(coin::value<U>(&coin_u_out) >= amount_u_min_out, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        transfer::public_transfer(coin_u_out, to);
    }

    #[test]
    public fun test_ensure(){
        let clock = clock::create_for_testing(&mut tx_context::dummy());
        ensure(&clock, 10000);
        clock::destroy_for_testing(clock);
    }

    #[test]
    #[expected_failure(abort_code = ERROR_EXPIRED)]
    public fun test_ensure_fail(){
        let clock = clock::create_for_testing(&mut tx_context::dummy());
        clock::increment_for_testing(&mut clock, 10001);
        ensure(&clock, 10000);
        clock::destroy_for_testing(clock);
    }
}