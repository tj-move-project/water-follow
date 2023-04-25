/// Uniswap v2 factory like program
module swap::factory {
    use std::string::{String};

    use sui::tx_context::{Self, TxContext};
    use sui::bag::{Self, Bag};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::event;

    use swap::type_helper;
    use swap::swap_utils;
    use swap::pair::{Self, PairMetadata};
    use swap::treasury::{Self, Treasury};

    const ZERO_ADDRESS: address = @zero;

    const ERROR_PAIR_ALREADY_CREATED: u64 = 0;
    const ERROR_PAIR_UNSORTED: u64 = 1;
    
    /// The container that holds all of AMM's liquidity pools
    struct Container has key {
        /// the ID of this container
        id: UID,
        /// AMM's liquidity pool collection.
        pairs: Bag,
        ///AMM's treasury.
        treasury: Treasury
    }

    /// Capability allow appoints new treasurer
    struct AdminCap has key, store {
        id: UID,
    }

    /// Emitted when liquidity pool is created from user.
    struct PairCreated has copy, drop {
        user: address,
        pair: String,
        coin_x: String,
        coin_y: String,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Container {
            id: object::new(ctx),
            pairs: bag::new(ctx),
            treasury: treasury::new(ZERO_ADDRESS)
        });

        transfer::transfer(AdminCap {
            id: object::new(ctx)
        }, tx_context::sender(ctx));
    }

    /// Creates a liquidity pool of two coins X and Y.
    /// The liquidity pool of the two coins must not exist yet.
    public fun create_pair<X, Y>(container: &mut Container, ctx: &mut TxContext) {
        //Ensure there is only one liquidity pool of two coins
        let lp_name = if (swap_utils::is_ordered<X, Y>()) {
            let lp_name = pair::get_lp_name<X, Y>();
            assert!(!bag::contains_with_type<String, PairMetadata<X, Y>>(&container.pairs, lp_name), ERROR_PAIR_ALREADY_CREATED);

            let pair = pair::create_pair<X, Y>(ctx);
            bag::add<String, PairMetadata<X, Y>>(&mut container.pairs, lp_name, pair);
            lp_name
        } else {
            let lp_name = pair::get_lp_name<Y, X>();
            assert!(!bag::contains_with_type<String, PairMetadata<Y, X>>(&container.pairs, lp_name), ERROR_PAIR_ALREADY_CREATED);

            let pair = pair::create_pair<Y, X>(ctx);
            bag::add<String, PairMetadata<Y, X>>(&mut container.pairs, lp_name, pair);
            lp_name
        };

        event::emit(PairCreated {
            pair: lp_name,
            user: tx_context::sender(ctx),
            coin_x: type_helper::get_type_name<X>(),
            coin_y: type_helper::get_type_name<Y>(),
        });
    }

    /// Whether the liquidity pool of the two coins has been created?
    public fun pair_is_created<X, Y>(container: &Container): bool {
        if (swap_utils::is_ordered<X, Y>()) {
            let lp_name = pair::get_lp_name<X, Y>();
            bag::contains_with_type<String, PairMetadata<X, Y>>(&container.pairs, lp_name)
        } else {
            let lp_name = pair::get_lp_name<Y, X>();
            bag::contains_with_type<String, PairMetadata<Y, X>>(&container.pairs, lp_name)
        }
    }

    /// Immutable borrows the `PairMetadata` of two coins X and Y.
    /// Two coins X and Y must be sorted.
    public fun borrow_pair<X, Y>(container: &Container): &PairMetadata<X, Y> {
        assert!(swap_utils::is_ordered<X, Y>(), ERROR_PAIR_UNSORTED);
        let lp_name = pair::get_lp_name<X, Y>();
        bag::borrow<String, PairMetadata<X, Y>>(&container.pairs, lp_name)
    }

    /// Mutable borrows the `PairMetadata` of two coins X and Y.
    /// Two coins X and Y must be sorted.
    public fun borrow_mut_pair<X, Y>(container: &mut Container): (&mut PairMetadata<X, Y>) {
        assert!(swap_utils::is_ordered<X, Y>(), ERROR_PAIR_UNSORTED);
        let lp_name = pair::get_lp_name<X, Y>();
        bag::borrow_mut<String, PairMetadata<X, Y>>(&mut container.pairs, lp_name)
    }

    /// Mutable borrows the `PairMetadata` of two coins X and Y and the immutable borrow the treasury of AMM.
    /// Two coins X and Y must be sorted.
    public fun borrow_mut_pair_and_treasury<X, Y>(container: &mut Container): (&mut PairMetadata<X, Y>, &Treasury) {
        assert!(swap_utils::is_ordered<X, Y>(), ERROR_PAIR_UNSORTED);
        let lp_name = pair::get_lp_name<X, Y>();
        (bag::borrow_mut<String, PairMetadata<X, Y>>(&mut container.pairs, lp_name), &container.treasury)
    }

    /// Immutable borrows the `Treasury` of AMM.
    public fun borrow_treasury(container: &Container): &Treasury {
        &container.treasury
    }

    /// Appoints a new treasurer to the treasury
    public entry fun set_fee_to(_: &mut AdminCap, container: &mut Container, fee_to: address) {
        treasury::appoint(&mut container.treasury, fee_to);
    }

    #[test_only]
    public fun dummy(ctx: &mut TxContext) {
        transfer::share_object(Container {
            id: object::new(ctx),
            pairs: bag::new(ctx),
            treasury: treasury::new(ZERO_ADDRESS)
        });
    } 
}