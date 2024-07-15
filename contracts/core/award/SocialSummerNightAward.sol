// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract SocialSummerNightAward  {

    address public governance;


    constructor () {
        governance = msg.sender;
    }

    function changeGovernance(address _newGovernance) public {
        require(msg.sender == governance, 'Not governance');
        governance = _newGovernance;
    }

    function governanceClaim(address erc20, address payable to, uint256 amount) public {
        require(msg.sender == governance, 'Not governance');
        if (erc20 == address(0)){
            to.transfer(amount);
        } else {
            IERC20(erc20).transfer(to, amount);
        }
    }

    receive() external payable {}
}
