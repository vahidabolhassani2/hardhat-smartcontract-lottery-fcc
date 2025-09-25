//Enter the lotteryy (paying some amount)
//Pick a random winner (verifiably random)
//Winner to be selected every X minutes -> completely automated
//Chainlink Oracle -> Randomness, Automated execution (Chainlink Keepers)

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

error Raffle__NotEnoughETHEntered(uint256 amountEntered, uint256 entranceFee);
error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__UpkeepNotNeeded(
  uint256 currentBalance,
  uint256 numPlayers,
  uint256 raffleState
);

contract Raffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
  enum RaffleState {
    OPEN,
    CALCULATING
  }

  event RequestSent(uint256 requestId, uint32 numWords);
  event RequestFulfilled(uint256 requestId, uint256[] randomWords);
  event RaffleEnter(address indexed player);
  event RequestedRaffleWinner(uint256 indexed requestId);
  event WinnerPicked(address indexed winner);

  //lottery variables

  struct RequestStatus {
    bool fulfilled; // whether the request has been successfully fulfilled
    bool exists; // whether a requestId exists
    uint256[] randomWords;
  }
  mapping(uint256 => RequestStatus)
    public s_requests; /* requestId --> requestStatus */

  /*ChainLink VRF Variables */

  uint256 private immutable i_entranceFee;
  uint256 private immutable i_subscriptionId;
  bytes32 private immutable i_gasLane;
  uint32 private immutable i_callbackGasLimit;
  uint256[] public s_requestIds;
  uint256 public s_lastRequestId;

  /*Lottery Variables */
  uint256 private immutable i_interval; // interval specifies the time between upkeeps
  uint256 private s_lastTimeStamp; // lastTimeStamp tracks the last upkeep performed
  address payable private s_recentWinner;
  RaffleState private s_raffleState;

  uint16 private constant REQUEST_CONFIRMATIONS = 3;
  uint32 private constant NUM_WORDS = 2;
  address payable[] private s_players;

  /**
   * HARDCODED FOR SEPOLIA
   * COORDINATOR: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B
   */

  /**Events */

  constructor(
    address vrfCoordinatorV2,
    uint256 entranceFee,
    bytes32 gasLane,
    uint256 subscriptionId,
    uint32 callbackGasLimit,
    uint256 interval
  ) VRFConsumerBaseV2Plus(vrfCoordinatorV2) {
    i_entranceFee = entranceFee;
    i_gasLane = gasLane;
    i_subscriptionId = subscriptionId;
    i_callbackGasLimit = callbackGasLimit;
    i_interval = interval;
    s_raffleState = RaffleState.OPEN;
    s_lastTimeStamp = block.timestamp;
  }

  function enterRaffle() public payable {
    // Require the sender to pay the specified amount
    // require(msg.value > i_entranceFee, "Must enter with a positive amount");
    if (msg.value < i_entranceFee) {
      revert Raffle__NotEnoughETHEntered(msg.value, i_entranceFee);
    }
    if (s_raffleState != RaffleState.OPEN) {
      revert Raffle__NotOpen();
    }

    s_players.push(payable(msg.sender));
    emit RaffleEnter(msg.sender);
  }

  function getEntranceFee() public view returns (uint256) {
    return i_entranceFee;
  }

  function getPlayer(uint256 index) public view returns (address payable) {
    return s_players[index];
  }

  function requestRandomWinner(
    bool enableNativePayment
  ) public returns (uint256 requestId) {
    requestId = s_vrfCoordinator.requestRandomWords(
      VRFV2PlusClient.RandomWordsRequest({
        keyHash: i_gasLane,
        subId: i_subscriptionId,
        requestConfirmations: REQUEST_CONFIRMATIONS,
        callbackGasLimit: i_callbackGasLimit,
        numWords: NUM_WORDS,
        extraArgs: VRFV2PlusClient._argsToBytes(
          VRFV2PlusClient.ExtraArgsV1({nativePayment: enableNativePayment})
        )
      })
    );
    s_requests[requestId] = RequestStatus({
      randomWords: new uint256[](0),
      exists: true,
      fulfilled: false
    });
    s_requestIds.push(requestId);
    s_lastRequestId = requestId;
    emit RequestSent(requestId, NUM_WORDS);
    emit RequestedRaffleWinner(requestId);

    return requestId;
  }

  function fulfillRandomWords(
    uint256 /*requestId*/,
    uint256[] calldata randomWords
  ) internal override {
    uint256 indexOfWinner = randomWords[0] % s_players.length;
    s_recentWinner = s_players[indexOfWinner];
    s_players = new address payable[](0);
    s_raffleState = RaffleState.OPEN;
    s_lastTimeStamp = block.timestamp;

    (bool success, ) = s_recentWinner.call{value: address(this).balance}("");
    if (!success) {
      revert Raffle__TransferFailed();
    }

    emit WinnerPicked(s_recentWinner);
  }

  function getRecentWinner() public view returns (address) {
    return s_recentWinner;
  }

  function checkUpkeep(
    bytes memory /*checkData*/
  ) public view override returns (bool, bytes memory /*performData*/) {
    bool isOpen = (s_raffleState == RaffleState.OPEN);
    bool hasPlayers = s_players.length > 0;
    bool hasBalance = address(this).balance > 0;
    bool timePassed = (block.timestamp - s_lastTimeStamp) > i_interval;

    bool upkeepNeeded = isOpen && hasPlayers && hasBalance && timePassed;

    return (upkeepNeeded, "0x0");
  }

  function performUpkeep(bytes calldata /*performData*/) external override {
    (bool upkeepNeeded, ) = checkUpkeep("");
    if (!upkeepNeeded) {
      revert Raffle__UpkeepNotNeeded(
        address(this).balance,
        s_players.length,
        uint256(s_raffleState)
      );
    }

    s_raffleState = RaffleState.CALCULATING;

    // Request a random winner
    uint256 requestId = requestRandomWinner(true);
    emit RequestedRaffleWinner(requestId);
  }
}
