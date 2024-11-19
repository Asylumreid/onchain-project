// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

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

    modifier whenTheSellerUpdatesTheStatus() {
        _;
    }

    function test_WhenUpdatingToShipped()
        external
        whenTheCallerIsKnown
        givenUpdatingTheStatus
        whenTheSellerUpdatesTheStatus
    {
        // it should succeed
    }

    function test_RevertWhen_UpdatingToReceivedAsSeller()
        external
        whenTheCallerIsKnown
        givenUpdatingTheStatus
        whenTheSellerUpdatesTheStatus
    {
        // it should revert
    }

    modifier whenTheBuyerUpdatesTheStatus() {
        _;
    }

    function test_WhenUpdatingToReceived()
        external
        whenTheCallerIsKnown
        givenUpdatingTheStatus
        whenTheBuyerUpdatesTheStatus
    {
        // it should succeed
    }

    function test_RevertWhen_UpdatingToShippedAsBuyer()
        external
        whenTheCallerIsKnown
        givenUpdatingTheStatus
        whenTheBuyerUpdatesTheStatus
    {
        // it should revert
    }

    function test_RevertWhen_TheCallerIsUnauthorized() external whenTheCallerIsKnown givenUpdatingTheStatus {
        // it should revert
    }

    modifier givenMarkingADispute() {
        _;
    }

    function test_WhenTheCallerIsTheBuyer() external whenTheCallerIsKnown givenMarkingADispute {
        // it should succeed if allowed
    }

    function test_WhenTheCallerIsTheSeller() external whenTheCallerIsKnown givenMarkingADispute {
        // it should succeed if allowed
    }

    function test_RevertWhen_TheStatusDoesNotAllowDisputes() external whenTheCallerIsKnown givenMarkingADispute {
        // it should revert
    }

    modifier givenHandlingADispute() {
        _;
    }

    function test_RevertWhen_TheHandlerIsUnauthorized() external whenTheCallerIsKnown givenHandlingADispute {
        // it should revert
    }

    function test_WhenTheHandlerResolvesToRefundTheBuyer() external whenTheCallerIsKnown givenHandlingADispute {
        // it should refund the buyer and transfer the fee
    }

    function test_WhenTheHandlerResolvesToPayTheSeller() external whenTheCallerIsKnown givenHandlingADispute {
        // it should pay the seller and transfer the fee
    }

    function test_RevertWhen_TheFeeCollectionIsInsufficient() external whenTheCallerIsKnown givenHandlingADispute {
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
