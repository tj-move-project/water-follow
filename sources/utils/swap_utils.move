module swap::swap_utils {
    use std::ascii;
    use std::type_name;
    use sui::coin::{Self, Coin};

    use swap::comparator;

    const EQUAL: u8 = 0;
    const SMALLER: u8 = 1;
    const GREATER: u8 = 2;

    const ERROR_INSUFFICIENT_INPUT_AMOUNT: u64 = 0;
    const ERROR_INSUFFICIENT_LIQUIDITY: u64 = 1;
    const ERROR_IDENTICAL_COIN: u64 = 2;
    const ERROR_EMPTY_ARRAY: u64 = 3;

    // FORMULA = (x * y) = k;
    // (x + dx)(y - dy) = k = xy;
    // dy = y - (x * y) / (x + dx)
    // dy = y * dx / (x + dx);
    public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64
    ): u64 {
        assert!(amount_in > 0, ERROR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERROR_INSUFFICIENT_LIQUIDITY);

        //TODO: Protocol fee is 0.3% being hard coded. Allow it to change
        let amount_in_with_fee = (amount_in as u256) * 997u256;
        let numerator = amount_in_with_fee * (reserve_out as u256);
        let denominator = (reserve_in as u256) * 1000u256 + amount_in_with_fee;
        ((numerator / denominator) as u64)
    }
    
    // FORMULA = (x * y) = k;
    // (x + dx)(y - dy) = k = xy;
    // dx = (x * y) / (y - dy) - x;
    // dx = (x * dy) / (y - dy);
    public fun get_amount_in(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64
    ): u64 {
        assert!(amount_out > 0, ERROR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERROR_INSUFFICIENT_LIQUIDITY);

        //TODO: Protocol fee is 0.3% being hard coded. Allow it to change
        let numerator = (reserve_in as u256) * (amount_out as u256) * 1000u256;
        let denominator = ((reserve_out as u256) - (amount_out as u256)) * 997u256;
        ((numerator / denominator) as u64) + 1u64
    }

    public fun quote(amount_in: u64, reserve_in: u64, reserve_out: u64): u64 {
        assert!(amount_in > 0, ERROR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERROR_INSUFFICIENT_LIQUIDITY);
        let amount_out = ((amount_in as u128) * (reserve_out as u128)) / (reserve_in as u128);
        (amount_out as u64)
    }

    public fun is_ordered<X, Y>(): bool {
        let x_name = type_name::into_string(type_name::get<X>());
        let y_name = type_name::into_string(type_name::get<Y>());

        let result = comparator::compare_u8_vector(ascii::into_bytes(x_name), ascii::into_bytes(y_name));
        assert!(!comparator::is_equal(&result), ERROR_IDENTICAL_COIN);
        
        comparator::is_smaller_than(&result)
    }

    public fun left_amount<T>(c: &Coin<T>, amount_desired: u64): u64 {
        assert!(coin::value(c) >= amount_desired, ERROR_INSUFFICIENT_INPUT_AMOUNT);
        coin::value(c) - amount_desired
    }

    #[test]
    fun test_get_amount_out() {
        let (reserve_in, reserve_out) = (10000, 50000);
        let amount_in = 1000;

        //amount_in = amount_in * 0.997 = 997
        //amount_out = (reserve_out * amount_in) / (reserve_in + amount_in) = (50000 * 997) / (10000 + 997) = 4533
        assert!(get_amount_out(amount_in, reserve_in, reserve_out) == 4533, 0);
    }

    #[test]
    fun test_get_amount_in() {
        let (reserve_in, reserve_out) = (10000, 50000);
        let amount_out = 1000;

        //amount_in = amount_in * 0.997 = 997
        //amount_out = ((reserve_in * amount_out) / (reserve_out - amount_out)) / 0.997 = ((10000 * 1000) / (50000 - 1000))/0.997 + 1= 205
        assert!(get_amount_in(amount_out, reserve_in, reserve_out) == 205, 0);
    }

    #[test]
    fun test_quote() {
        let (reserve_in, reserve_out) = (10000, 50000);
        let amount_in = 1000;
        //amount_in / amount_out = reverse_in / reverse_out
        //amount_out = (amount_in * reverse_out) / reverse_in = (1000 * 50000) / 10000 = 5000
        assert!(quote(amount_in, reserve_in, reserve_out) == 5000, 0);
    }
}