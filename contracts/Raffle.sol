//Enter the lotteryy (paying some amount)
//Pick a random winner (verifiably random)
//Winner to be selected every X minutes -> completely automated
//Chainlink Oracle -> Randomness, Automated execution (Chainlink Keepers)

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

contract Raffle {
  /**State Variables */
  uint256 private immutable i_entranceFee;
  address payable[] private s_players;

  /**Events */
  event RaffleEnter(address indexed player);

  error Raffle__NotEnoughETHEntered(uint256 amountEntered, uint256 entranceFee);

  constructor(uint256 entranceFee) {
    i_entranceFee = entranceFee;
  }

  function enterRaffle() public payable {
    // Require the sender to pay the specified amount
    // require(msg.value > i_entranceFee, "Must enter with a positive amount");
    if (msg.value < i_entranceFee) {
      revert Raffle__NotEnoughETHEntered(msg.value, i_entranceFee);
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

  //   function pickRandomWinner() public {
  //     // Logic to pick a random winner
  //   }
}
