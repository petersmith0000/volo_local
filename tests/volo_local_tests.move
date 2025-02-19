#[test_only]
module volo_local::volo_local_tests;

use sui::test_scenario::{Self, Scenario, next_tx};
use sui::coin::{Self, mint, Coin};
use sui::sui::SUI;
use sui_system::sui_system::{Self, SuiSystemState, create};
use volo_local::native_pool::{Self, NativePool};
use volo_local::cert::{Self, Metadata, CERT};
use sui_system::governance_test_utils::{create_validator_for_testing, create_sui_system_state_for_testing};

const ADMIN: address = @0x0;
const USER: address = @0x0819;
const MIST_PER_SUI: u64 = 1_000_000_000;
const TEST_SHARES: u64 = 100*MIST_PER_SUI;



#[test]
fun test_basic_stake_unstake(){
    let mut scenario = test_scenario::begin(ADMIN);
    {
        let ctx = scenario.ctx();
        cert::test_init(ctx);
        native_pool::test_init(ctx);
        create_sui_system_state_for_testing(vector[create_validator_for_testing(@0xAB1, 100, ctx)], 100, 100, ctx);
        
    };

    scenario.next_tx(USER);
    {
        let sui = coin::mint_for_testing<SUI>(TEST_SHARES, scenario.ctx());
        let mut pool = test_scenario::take_shared<NativePool>(&scenario);
        let mut metadata = test_scenario::take_shared<Metadata<CERT>>(&scenario);
        let mut system_state = test_scenario::take_shared<SuiSystemState>(&scenario);

        native_pool::stake(
            &mut pool, 
            &mut metadata, 
            &mut system_state,
             sui,
              scenario.ctx());

        test_scenario::return_shared(pool);
        test_scenario::return_shared(metadata);
        test_scenario::return_shared(system_state);  
    };

    scenario.next_tx(USER);
    {
        let cert_coin = scenario.take_from_sender<Coin<CERT>>();
        assert!(cert_coin.balance().value() == TEST_SHARES, 100);
        test_scenario::return_to_sender(&scenario, cert_coin);
    };

    scenario.next_tx(USER);
    {
        let cert_coin = scenario.take_from_sender<Coin<CERT>>();
        let mut pool = test_scenario::take_shared<NativePool>(&scenario);
        let mut metadata = test_scenario::take_shared<Metadata<CERT>>(&scenario);
        let mut system_state = test_scenario::take_shared<SuiSystemState>(&scenario);
        native_pool::unstake(&mut pool, &mut metadata, &mut system_state, cert_coin, scenario.ctx());

        test_scenario::return_shared(pool);
        test_scenario::return_shared(metadata);
        test_scenario::return_shared(system_state);  
    };

    scenario.next_tx(USER);
    {
        let sui_balance = scenario.take_from_sender<Coin<SUI>>();
        assert!(sui_balance.balance().value() == TEST_SHARES, 100);
        test_scenario::return_to_sender(&scenario, sui_balance);
    };


    test_scenario::end(scenario);
}

#[test]
fun test_ratio_update_operations() {
    let mut scenario = test_scenario::begin(ADMIN);
    {
        let ctx = scenario.ctx();
        cert::test_init(ctx);
        native_pool::test_init(ctx);
        create_sui_system_state_for_testing(
            vector[create_validator_for_testing(@0xAB1, 100, ctx)],
            100,
            100,
            ctx
        );
    };

    // Transaction 1: Initial stake at ratio = 1.
    scenario.next_tx(USER);
    {
        let sui = coin::mint_for_testing<SUI>(TEST_SHARES, scenario.ctx());
        let mut pool = test_scenario::take_shared<NativePool>(&scenario);
        let mut metadata = test_scenario::take_shared<Metadata<CERT>>(&scenario);
        let mut system_state = test_scenario::take_shared<SuiSystemState>(&scenario);

        // Stake TEST_SHARES SUI; minted CERT amount equals TEST_SHARES (since ratio is 1).
        native_pool::stake(&mut pool, &mut metadata, &mut system_state, sui, scenario.ctx());

        test_scenario::return_shared(pool);
        test_scenario::return_shared(metadata);
        test_scenario::return_shared(system_state);
    };

    // Transaction 2: Update ratio from 1 to 2.
    // To update the ratio, the pool requires additional SUI:
    // required_staked = total_shares * new_ratio = TEST_SHARES * 2,
    // so extra deposit = TEST_SHARES.
    scenario.next_tx(USER);
    {
        let extra_sui = coin::mint_for_testing<SUI>(TEST_SHARES, scenario.ctx());
        let mut pool = test_scenario::take_shared<NativePool>(&scenario);
        let metadata = test_scenario::take_shared<Metadata<CERT>>(&scenario);

        native_pool::update_ratio(&mut pool, &metadata, 2, extra_sui, scenario.ctx());

        // Verify new ratio and the updated staked amount.
        assert!(pool.get_ratio(&metadata) == 2, 200);
        let pool_staked = &pool.get_staked();
        assert!(pool_staked == 2 * TEST_SHARES, 201);

        test_scenario::return_shared(pool);
        test_scenario::return_shared(metadata);
    };

    // Transaction 3: Stake additional SUI at the new ratio (2).
    scenario.next_tx(USER);
    {
        let sui_new = coin::mint_for_testing<SUI>(TEST_SHARES, scenario.ctx());
        let mut pool = test_scenario::take_shared<NativePool>(&scenario);
        let mut metadata = test_scenario::take_shared<Metadata<CERT>>(&scenario);
        let mut system_state = test_scenario::take_shared<SuiSystemState>(&scenario);

        // At ratio 2, staking TEST_SHARES SUI mints (TEST_SHARES / 2) shares.
        native_pool::stake(&mut pool, &mut metadata, &mut system_state, sui_new, scenario.ctx());

        test_scenario::return_shared(pool);
        test_scenario::return_shared(metadata);
        test_scenario::return_shared(system_state);
    };

    // Transaction 4: Verify that the certificate minted in Transaction 3 has the expected shares.
    scenario.next_tx(USER);
    {
        let cert_coin = scenario.take_from_sender<Coin<CERT>>();
        // Expect minted shares = TEST_SHARES / 2.
        assert!(cert_coin.balance().value() == TEST_SHARES / 2, 202);
        test_scenario::return_to_sender(&scenario, cert_coin);
    };

    // Transaction 5: Unstake the certificate minted in Transaction 3.
    scenario.next_tx(USER);
    {
        let cert_coin = scenario.take_from_sender<Coin<CERT>>();
        let mut pool = test_scenario::take_shared<NativePool>(&scenario);
        let mut metadata = test_scenario::take_shared<Metadata<CERT>>(&scenario);
        let mut system_state = test_scenario::take_shared<SuiSystemState>(&scenario);

        native_pool::unstake(&mut pool, &mut metadata, &mut system_state, cert_coin, scenario.ctx());

        test_scenario::return_shared(pool);
        test_scenario::return_shared(metadata);
        test_scenario::return_shared(system_state);
    };

    // Transaction 6: Verify that unstaking returns SUI equal to (minted shares * new ratio)
    // which should be (TEST_SHARES/2 * 2) = TEST_SHARES.
    scenario.next_tx(USER);
    {
        let returned_sui = scenario.take_from_sender<Coin<SUI>>();
        assert!(returned_sui.balance().value() == TEST_SHARES, 203);
        test_scenario::return_to_sender(&scenario, returned_sui);
    };

    test_scenario::end(scenario);
}

