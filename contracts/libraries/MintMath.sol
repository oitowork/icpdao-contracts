// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;
import "hardhat/console.sol";

library MintMath {

    struct MintArgs {
        uint128 p;
        uint16 aNumerator;
        uint16 aDenominator;
        uint16 bNumerator;
        uint16 bDenominator;
        uint16 c;
        uint16 d;
    }

    struct Anchor {
        MintArgs args;
        uint256 lastTimestamp;
        uint256 n;
    }

    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = a * b
        // Compute the product mod 2**256 and mod 2**256 - 1
        // then use the Chinese Remainder Theorem to reconstruct
        // the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2**256 + prod0
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        // Make sure the result is less than 2**256.
        // Also prevents denominator == 0
        require(denominator > prod1);

        ///////////////////////////////////////////////
        // 512 by 256 division.
        ///////////////////////////////////////////////

        // Make division exact by subtracting the remainder from [prod1 prod0]
        // Compute remainder using mulmod
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // Subtract 256 bit number from 512 bit number
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // Factor powers of two out of denominator
        // Compute largest power of two divisor of denominator.
        // Always >= 1.
        uint256 twos = (0-denominator) & denominator;
        // Divide denominator by power of two
        assembly {
            denominator := div(denominator, twos)
        }

        // Divide [prod1 prod0] by the factors of two
        assembly {
            prod0 := div(prod0, twos)
        }
        // Shift in bits from prod1 into prod0. For this we need
        // to flip `twos` such that it is 2**256 / twos.
        // If twos is zero, then it becomes one
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        // Invert denominator mod 2**256
        // Now that denominator is an odd number, it has an inverse
        // modulo 2**256 such that denominator * inv = 1 mod 2**256.
        // Compute the inverse by starting with a seed that is correct
        // correct for four bits. That is, denominator * inv = 1 mod 2**4
        uint256 inv = (3 * denominator) ^ 2;
        // Now use Newton-Raphson iteration to improve the precision.
        // Thanks to Hensel's lifting lemma, this also works in modular
        // arithmetic, doubling the correct bits in each step.
        inv *= 2 - denominator * inv; // inverse mod 2**8
        inv *= 2 - denominator * inv; // inverse mod 2**16
        inv *= 2 - denominator * inv; // inverse mod 2**32
        inv *= 2 - denominator * inv; // inverse mod 2**64
        inv *= 2 - denominator * inv; // inverse mod 2**128
        inv *= 2 - denominator * inv; // inverse mod 2**256

        // Because the division is now exact we can divide by multiplying
        // with the modular inverse of denominator. This will give us the
        // correct result modulo 2**256. Since the precoditions guarantee
        // that the outcome is less than 2**256, this is the final result.
        // We don't need to compute the high bits of the result and prod1
        // is no longer required.
        result = prod0 * inv;
        return result;
    }

    function initialize(
        Anchor storage last,
        MintArgs memory args,
        uint256 time
    ) internal {
        last.args = args;
        last.lastTimestamp = time / 86400 * 86400;
        last.n = 0;
    }

    function total(
        Anchor storage last,
        uint256 endTimestamp
    ) internal returns (uint256) {
        uint256 d = last.args.d;
        uint256 p = last.args.p;
        uint256 an = last.args.aNumerator;
        uint256 ad = last.args.aDenominator;
        uint256 bn = last.args.bNumerator;
        uint256 bd = last.args.bDenominator;
        uint256 c = last.args.c;

        uint256 beginN = last.n + 1;
        uint256 n = last.n + (endTimestamp / 86400 * 86400 - last.lastTimestamp) / 86400;

        uint256 result;
        uint256 lastCoefficient;
        uint256 lastValue;

        for (uint256 i = beginN; i <= n; i++) {
            uint256 coefficient = mulDiv(bn, i, bd);
            uint256 value = lastValue;
            if (coefficient != lastCoefficient || i == beginN) {
                value = coefficient + c;
                value = (((an ** value ) * p) * 1e12) / (ad ** value);
                value += d * 1e12;
                if (value < 0) value = 0;
                lastValue = value;
                lastCoefficient = coefficient;
                console.log("calculate");
            }
            result += value;
            console.log(i, lastCoefficient, lastValue, result);
        }

        last.lastTimestamp = endTimestamp;
        last.n = n;
        result = result / 1e12;
        return result;
    }
}