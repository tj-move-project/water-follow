/// Uniswap v2 pair like program
module swap::pair {
    use std::string::{Self, String};
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Supply};
    use sui::transfer;
    use sui::event;

    use swap::math;
    use swap::type_helper;
    use swap::treasury::{Self, Treasury};

    friend swap::factory;

    /// 
    /// constants 
    /// 
    const MINIMUM_LIQUIDITY: u64 = 1000;
    const ZERO_ADDRESS: address = @zero;

    /// 
    /// errors
    /// 
    const ERROR_INSUFFICIENT_LIQUIDITY_MINTED :u64 = 0;
    const ERROR_INSUFFICIENT_LIQUIDITY_BURNED :u64 = 1;
    const ERROR_INSUFFICIENT_INPUT_AMOUNT: u64 = 2;
    const ERROR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 3;
    const ERROR_INSUFFICIENT_LIQUIDITY: u64 = 4;
    const ERROR_K: u64 = 5;

    /// LP Coins represent the liquidity of two coins X and Y
    struct LP<phantom X, phantom Y> has drop {}

    /// Metadata of each liquidity pool.
    struct PairMetadata<phantom X, phantom Y> has key, store {
        /// the ID of liquidity pool of two coins X and Y
        id: UID,
        /// the reserve of coin X in pool
        reserve_x: Coin<X>,
        /// the reserve of coin Y in pool
        reserve_y: Coin<Y>,
        /// the last value of k
        k_last: u128,
        /// the total supply of LP coin
        lp_supply: Supply<LP<X, Y>>,
    }

    /// Emitted when liquidity is added from user
    struct LiquidityAdded has copy, drop {
        user: address,
        coin_x: String,
        coin_y: String,
        amount_x: u64,
        amount_y: u64,
        liquidity: u64,
        fee: u64
    }

    /// Emitted when liquidity is removed from user
    struct LiquidityRemoved has copy, drop {
        user: address,
        coin_x: String,
        coin_y: String,
        amount_x: u64,
        amount_y: u64,
        liquidity: u64,
        fee: u64
    }

    /// Emitted when coin X is swapped to coin Y from user
    struct Swapped has copy, drop {
        user: address,
        coin_x: String,
        coin_y: String,
        amount_x_in: u64,
        amount_y_in: u64,
        amount_x_out: u64,
        amount_y_out: u64,
    }

    /// Returns the reserve of coins X and Y.
    public fun get_reserves<X, Y>(metadata: &PairMetadata<X, Y>): (u64, u64) {
        (
            coin::value<X>(&metadata.reserve_x),
            coin::value<Y>(&metadata.reserve_y),
        )
    }


    /// Returns the total supply of LP coin.
    public fun total_lp_supply<X, Y>(metadata: &PairMetadata<X, Y>): u64 {
       balance::supply_value<LP<X, Y>>(&metadata.lp_supply)
    }

    /// Returns the k last.
    public fun k<X, Y>(metadata: &PairMetadata<X, Y>): u128 {
        metadata.k_last
    }


    /// Updates the k last.
    fun update_k_last<X, Y>(metadata: &mut PairMetadata<X, Y>) {
        let (reserve_x, reserve_y) = get_reserves(metadata);
        metadata.k_last = (reserve_x as u128) * (reserve_y as u128);
    }

    /// LP name includes type name of coin X and Y.
    public fun get_lp_name<X, Y>(): String {
        let lp_name = string::utf8(b"LP-");
        string::append(&mut lp_name, type_helper::get_type_name<X>());
        string::append_utf8(&mut lp_name, b"-");
        string::append(&mut lp_name, type_helper::get_type_name<Y>());

        lp_name
    }

    /// Creates a liquidity pool of two coins X and Y.
    public(friend) fun create_pair<X, Y>(ctx: &mut TxContext): PairMetadata<X, Y> {        
        let lp_supply = balance::create_supply<LP<X, Y>>(LP<X, Y> {});
        let pair_id = object::new(ctx);

        PairMetadata {
            id: pair_id,
            reserve_x: coin::zero<X>(ctx),
            reserve_y: coin::zero<Y>(ctx),
            k_last: 0,
            lp_supply,
        }
    }

    /// Deposits coin X to liquidity pool.
    fun deposit_x<X, Y>(metadata: &mut PairMetadata<X, Y>, coin_x: Coin<X>) {
        coin::join(&mut metadata.reserve_x, coin_x);
    }

    /// Deposits coin Y to liquidity pool.
    fun deposit_y<X, Y>(metadata: &mut PairMetadata<X, Y>, coin_y: Coin<Y>) {
        coin::join(&mut metadata.reserve_y, coin_y);
    }

    /// Returns an LP coin worth `amount`
    fun mint_lp<X, Y>(metadata: &mut PairMetadata<X, Y>, amount: u64, ctx: &mut TxContext): Coin<LP<X, Y>> {
        let lp_balance = balance::increase_supply<LP<X, Y>>(&mut metadata.lp_supply, amount);
        let lp = coin::from_balance<LP<X, Y>>(lp_balance, ctx);
        lp
    }

    /// Burns an LP coin
    fun burn_lp<X, Y>(metadata: &mut PairMetadata<X, Y>, lp_coin: Coin<LP<X, Y>>) {
        let lp_balance = coin::into_balance<LP<X, Y>>(lp_coin);
        balance::decrease_supply(&mut metadata.lp_supply, lp_balance);
    }

    /// Extract an X coin worth `amount` from the reserves of the liquidity pool.
    fun extract_x<X, Y>(metadata: &mut PairMetadata<X, Y>, amount: u64, ctx: &mut TxContext): Coin<X> {
        coin::split(&mut metadata.reserve_x, amount, ctx)
    }

    /// Extract an Y coin worth `amount` from the reserves of the liquidity pool.
    fun extract_y<X, Y>(metadata: &mut PairMetadata<X, Y>, amount: u64, ctx: &mut TxContext): Coin<Y> {
        coin::split(&mut metadata.reserve_y, amount, ctx)
    }
    
    /// Mints protocol fee.
    fun mint_fee<X, Y>(metadata: &mut PairMetadata<X, Y>, fee_to: address, ctx: &mut TxContext): u64 {
        let fee = 0u64;
        let (reserve_x, reserve_y) = get_reserves(metadata);
        if (fee_to != ZERO_ADDRESS) {
            if (metadata.k_last != 0) {
                let rook_k = math::sqrt_u128((reserve_x as u128) * (reserve_y as u128));
                let rook_k_last = math::sqrt_u128(metadata.k_last);
                if (rook_k > rook_k_last) {
                    let total_supply = (total_lp_supply<X, Y>(metadata) as u128);
                    let numerator = total_supply * (rook_k - rook_k_last);
                    let denominator = (rook_k * 5) + rook_k_last;
                    fee = (numerator / denominator as u64);
                    if (fee > 0) {
                        let lp_coin = mint_lp<X, Y>(metadata, fee, ctx);
                        transfer::public_transfer(lp_coin, fee_to);
                    }
                };
            };
        };

        fee
    }

    /// Mints LP coins corresponding to the amount of X or Y coins deposited into the liquidity pool.
    /// The coins must be deposited into the liquidity pool before calling this function.
    public fun mint<X, Y>(metadata: &mut PairMetadata<X, Y>, treasury: &Treasury, coin_x: Coin<X>, coin_y: Coin<Y>,  ctx: &mut TxContext): (Coin<LP<X, Y>>) {
        let (reserve_x, reserve_y) = get_reserves(metadata);
        let amount_x = coin::value<X>(&coin_x);
        let amount_y = coin::value<Y>(&coin_y);

        //Minting protocol fee
        let fee = mint_fee<X, Y>(metadata, treasury::treasurer(treasury), ctx);
        let total_supply = (total_lp_supply<X, Y>(metadata) as u128);
        let liquidity = if (total_supply == 0) {
            let liq = math::sqrt_u128((amount_x  as u128) * (amount_y as u128));
            assert!(liq > (MINIMUM_LIQUIDITY as u128), ERROR_INSUFFICIENT_LIQUIDITY_MINTED);
            liq = liq - (MINIMUM_LIQUIDITY as u128);
            //A small amount of initial liquidity will be sent to zero address ensuring liquidity is never lost
            let lp_genesis = mint_lp<X, Y>(metadata, MINIMUM_LIQUIDITY, ctx);
            transfer::public_transfer(lp_genesis, ZERO_ADDRESS);

            (liq as u64)
        } else {
            let liq = math::min_u128((amount_x as u128) * total_supply / (reserve_x as u128), (amount_y as u128) * total_supply / (reserve_y as u128));
            (liq as u64)
        };

        assert!(liquidity > 0, ERROR_INSUFFICIENT_LIQUIDITY_MINTED);
        let lp_coin = mint_lp<X, Y>(metadata, liquidity, ctx);

        //Deposit new coins to pool
        deposit_x<X,Y>(metadata, coin_x);
        deposit_y<X,Y>(metadata, coin_y);

        //Update k last
        update_k_last<X, Y>(metadata);

        event::emit(LiquidityAdded {
            user: tx_context::sender(ctx),
            coin_x: type_helper::get_type_name<X>(),
            coin_y: type_helper::get_type_name<Y>(),
            amount_x,
            amount_y,
            liquidity,
            fee
        });

        lp_coin
    }

    /// Burns LP coin and return X and Y coins of corresponding value.
    public fun burn<X, Y>(metadata: &mut PairMetadata<X, Y>, treasury: &Treasury, lp_coin: Coin<LP<X, Y>>, ctx: &mut TxContext): (Coin<X>, Coin<Y>) {
        let (reserve_x, reserve_y) = get_reserves<X, Y>(metadata);
        let liquidity = coin::value<LP<X, Y>>(&lp_coin);

        let fee = mint_fee<X, Y>(metadata, treasury::treasurer(treasury), ctx);

        let total_supply = (total_lp_supply<X, Y>(metadata) as u128);
        let amount_x = ((liquidity as u128) * (reserve_x as u128) / total_supply as u64);
        let amount_y = ((liquidity as u128) * (reserve_y as u128) / total_supply as u64);

        assert!(amount_x > 0 && amount_y > 0, ERROR_INSUFFICIENT_LIQUIDITY_BURNED);
        burn_lp(metadata, lp_coin);
        // Withdraw expected amount from reserves
        let coin_x_out = extract_x<X, Y>(metadata, amount_x, ctx);
        let coin_y_out = extract_y<X, Y>(metadata, amount_y, ctx);
        //Update k last
        update_k_last<X, Y>(metadata);

        event::emit(LiquidityRemoved {
            user: tx_context::sender(ctx),
            coin_x: type_helper::get_type_name<X>(),
            coin_y: type_helper::get_type_name<Y>(),
            amount_x,
            amount_y,
            liquidity,
            fee
        });

        (coin_x_out, coin_y_out)
    }

    /// Swaps X coins to Y coins or Y coins to X coins based on the "constant product formula".
    /// The coins must be deposited into the liquidity pool before calling this function.
    public fun swap<X, Y>(metadata: &mut PairMetadata<X, Y>, coin_x: Coin<X>, amount_x_out: u64, coin_y: Coin<Y>, amount_y_out: u64, ctx: &mut TxContext): (Coin<X>, Coin<Y>) {
        assert!(amount_x_out > 0 || amount_y_out > 0, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        let (reserve_x_before_swap, reserve_y_before_swap) = get_reserves(metadata);
        assert!(amount_x_out < reserve_x_before_swap && amount_y_out < reserve_y_before_swap, ERROR_INSUFFICIENT_LIQUIDITY);

        let amount_x_in = coin::value<X>(&coin_x);
        let amount_y_in = coin::value<Y>(&coin_y);
        assert!(amount_x_in > 0 || amount_y_in > 0, ERROR_INSUFFICIENT_INPUT_AMOUNT);
        //Deposit new coins to pool
        deposit_x<X,Y>(metadata, coin_x);
        deposit_y<X,Y>(metadata, coin_y);

        // Withdraw expected amount from reserves.
        let coin_x_out = extract_x<X, Y>(metadata, amount_x_out, ctx);
        let coin_y_out = extract_y<X, Y>(metadata, amount_y_out, ctx);
        let (reserve_x_after_swap, reserve_y_after_swap) = get_reserves<X, Y>(metadata);

        //TODO: Protocol fee is 0.3% being hard coded. Allow it to change
        let balance_x_adjusted = ((reserve_x_after_swap as u256) * 1000u256 ) - ((amount_x_in as u256) * 3u256);
        let balance_y_adjusted = ((reserve_y_after_swap as u256) * 1000u256) - ((amount_y_in as u256) * 3u256);
        //Ensure K is correct
        assert!(balance_x_adjusted * balance_y_adjusted >= (reserve_x_before_swap as u256) * (reserve_y_before_swap as u256) * (1000u256 * 1000u256), ERROR_K);

        event::emit(Swapped {
            user: tx_context::sender(ctx),
            coin_x: type_helper::get_type_name<X>(),
            coin_y: type_helper::get_type_name<Y>(),
            amount_x_in,
            amount_y_in,
            amount_x_out,
            amount_y_out
        });

        (coin_x_out, coin_y_out)
    }

    #[test_only]
    public fun dummy_pair<X, Y>(ctx: &mut TxContext) {
        let pair = PairMetadata {
            id: object::new(ctx),
            reserve_x: coin::zero<X>(ctx),
            reserve_y: coin::zero<Y>(ctx),
            k_last: 0,
            lp_supply: balance::create_supply(LP<X, Y> {})
        };
        transfer::share_object(pair);
    }

    #[test_only]
    public fun add_liquidity<X, Y>(pair: &mut PairMetadata<X, Y>, treasury: &Treasury, amount_x: u64, amount_y: u64, to: address, ctx: &mut TxContext) {
        let lp = mint(pair, treasury, coin::mint_for_testing<X>(amount_x, ctx), coin::mint_for_testing<Y>(amount_y, ctx), ctx);
        transfer::public_transfer(lp, to);
    }

    #[test_only]
    public fun remove_liquidity<X, Y>(pair: &mut PairMetadata<X, Y>, treasury: &Treasury, lp: Coin<LP<X, Y>>, to: address, ctx: &mut TxContext) {
        let (coin_x, coin_y) = burn(pair, treasury, lp, ctx);
        transfer::public_transfer(coin_x, to);
        transfer::public_transfer(coin_y, to);
    }

    #[test_only]
    public fun swap_x_to_y<X, Y>(pair: &mut PairMetadata<X, Y>, amount_x_in: u64, amount_y_out: u64, to: address, ctx: &mut TxContext) {
        let (coin_x, coin_y) = swap<X, Y>(pair, coin::mint_for_testing<X>(amount_x_in, ctx), 0, coin::zero<Y>(ctx), amount_y_out, ctx);
        assert!(coin::value(&coin_x) == 0 && coin::value(&coin_y) == amount_y_out, 0);
        coin::destroy_zero(coin_x);
        transfer::public_transfer(coin_y, to);
    }

    #[test_only]
    public fun swap_y_to_x<X, Y>(pair: &mut PairMetadata<X, Y>, amount_y_in: u64, amount_x_out: u64, to: address, ctx: &mut TxContext) {
        let (coin_x, coin_y) = swap<X, Y>(pair, coin::zero<X>(ctx), amount_x_out, coin::mint_for_testing<Y>(amount_y_in, ctx), 0, ctx);
        assert!(coin::value(&coin_y) == 0 && coin::value(&coin_x) == amount_x_out, 0);
        coin::destroy_zero(coin_y);
        transfer::public_transfer(coin_x, to);
    }
}