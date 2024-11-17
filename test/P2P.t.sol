// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract WhenGivenWhenTest {
    function test_RevertWhen_TheCallerIsUnknown() external {
        // it should revert
    }

    modifier whenTheCallerIsKnown() {
        _;
    }

    modifier givenCreatingAListing() {
        _;
    }

    function test_RevertWhen_ThePriceIs0() external whenTheCallerIsKnown givenCreatingAListing {
        // it should revert
    }

    function test_RevertWhen_TheTitleIsEmpty() external whenTheCallerIsKnown givenCreatingAListing {
        // it should revert
    }

    function test_WhenTheInputIsValid() external whenTheCallerIsKnown givenCreatingAListing {
        // it should succeed
    }

    modifier givenInitiatingABuy() {
        _;
    }

    function test_WhenTheAllowanceIsSufficient() external whenTheCallerIsKnown givenInitiatingABuy {
        // it should succeed
    }

    function test_RevertWhen_TheAllowanceIsInsufficient() external whenTheCallerIsKnown givenInitiatingABuy {
        // it should revert
    }

    function test_RevertWhen_TheBuyerIsAlsoTheSeller() external whenTheCallerIsKnown givenInitiatingABuy {
        // it should revert
    }

    function test_RevertWhen_TheListingIsAlreadyPurchased() external whenTheCallerIsKnown givenInitiatingABuy {
        // it should revert
    }

    modifier givenUpdatingTheStatus() {
        _;
    }

    modifier whenTheCallerIsTheSeller() {
        _;
    }

    function test_WhenUpdatingToShipped()
        external
        whenTheCallerIsKnown
        givenUpdatingTheStatus
        whenTheCallerIsTheSeller
    {
        // it should succeed
    }

    function test_RevertWhen_UpdatingToReceivedAsSeller()
        external
        whenTheCallerIsKnown
        givenUpdatingTheStatus
        whenTheCallerIsTheSeller
    {
        // it should revert
    }

    modifier whenTheCallerIsTheBuyer() {
        _;
    }

    function test_WhenUpdatingToReceived()
        external
        whenTheCallerIsKnown
        givenUpdatingTheStatus
        whenTheCallerIsTheBuyer
    {
        // it should succeed
    }

    function test_RevertWhen_UpdatingToShippedAsBuyer()
        external
        whenTheCallerIsKnown
        givenUpdatingTheStatus
        whenTheCallerIsTheBuyer
    {
        // it should revert
    }

    function test_RevertWhen_TheCallerIsUnauthorized() external whenTheCallerIsKnown givenUpdatingTheStatus {
        // it should revert
    }

    modifier givenConfirmingATransaction() {
        _;
    }

    function test_WhenTheShipmentIsCompleted() external whenTheCallerIsKnown givenConfirmingATransaction {
        // it should succeed
    }

    function test_RevertWhen_TheShipmentIsNotCompleted() external whenTheCallerIsKnown givenConfirmingATransaction {
        // it should revert
    }

    modifier givenWithdrawingFunds() {
        _;
    }

    function test_WhenTheTransactionIsCompleted() external whenTheCallerIsKnown givenWithdrawingFunds {
        // it should succeed
    }

    function test_RevertWhen_TheTransactionIsIncomplete() external whenTheCallerIsKnown givenWithdrawingFunds {
        // it should revert
    }

    modifier givenCancellingAListing() {
        _;
    }

    function test_WhenTheListingIsValid() external whenTheCallerIsKnown givenCancellingAListing {
        // it should succeed
    }

    function test_RevertWhen_TheListingIsInvalid() external whenTheCallerIsKnown givenCancellingAListing {
        // it should revert
    }

    modifier givenFetchingAListing() {
        _;
    }

    function test_WhenTheListingExists() external whenTheCallerIsKnown givenFetchingAListing {
        // it should return the correct listing
    }

    function test_RevertWhen_TheListingDoesNotExist() external whenTheCallerIsKnown givenFetchingAListing {
        // it should revert
    }
}
