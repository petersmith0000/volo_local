// This is a clone of volo staked sui for localnet testing purposes only
// three function stake, unstake, update_ratio
// SPDX-License-Identifier: MIT
module volo_local::native_pool;

use volo_local::cert::{Metadata, CERT, mint, burn, total_supply};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui_system::sui_system::SuiSystemState;

#[allow(lint(coin_field))]
public struct NativePool has key {
    id: UID,
    staked: Coin<SUI>,
    ratio: u64,
}

const EInsufficientSui: u64 = 1;
const EInvalidAmount: u64 = 2;

fun init(ctx: &mut TxContext) {
    transfer::share_object(NativePool {
        id: object::new(ctx),
        staked: coin::zero<SUI>(ctx),
        ratio: 1,
    });
}

public entry fun stake(
    self: &mut NativePool,
    metadata: &mut Metadata<CERT>,
    _wrapper: &mut SuiSystemState,
    coin: Coin<SUI>,
    ctx: &mut TxContext
) {
    let amount = coin.balance().value();
    assert!(amount % self.ratio == 0, EInvalidAmount); // Ensure exact division
    let shares = amount / self.ratio; // Calculate shares using ratio
    
    coin::join(&mut self.staked, coin);
    let cert = mint(metadata, shares, ctx);
    transfer::public_transfer(cert, tx_context::sender(ctx));

    
}

public entry fun unstake(
    self: &mut NativePool,
    metadata: &mut Metadata<CERT>,
    _wrapper: &SuiSystemState,
    cert: Coin<CERT>,
    ctx: &mut TxContext
) {
    let shares = cert.balance().value();
    burn(metadata, cert);
    let amount = shares * self.ratio;
    let coin = coin::split(&mut self.staked, amount, ctx);
    transfer::public_transfer(coin, tx_context::sender(ctx));
}

public entry fun update_ratio(
    self: &mut NativePool,
    metadata: &Metadata<CERT>,
    new_ratio: u64,
    mut sui_coin: Coin<SUI>,
    ctx: &mut TxContext
) {
    let total_shares = total_supply(metadata);
    let current_staked = coin::value(&self.staked);
    let required_staked = total_shares * new_ratio;

    if (required_staked > current_staked) {
        let needed = required_staked - current_staked;
        let available = coin::value(&sui_coin);
        assert!(available >= needed, EInsufficientSui);
        let coin_to_take = coin::split(&mut sui_coin, needed, ctx);
        coin::join(&mut self.staked, coin_to_take);
    } else if (required_staked < current_staked) {
        let excess = current_staked - required_staked;
        let coin_to_return = coin::split(&mut self.staked, excess, ctx);
        transfer::public_transfer(coin_to_return, tx_context::sender(ctx));
    };

    self.ratio = new_ratio;
    transfer::public_transfer(sui_coin, tx_context::sender(ctx));
}


#[test_only]
public fun test_init(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun get_staked(pool: &NativePool): u64 {
    coin::value(&pool.staked)
}

#[test_only]
public fun get_ratio(pool: &NativePool): u64 {
    pool.ratio
}
