//
//  Vector3.swift
//  OwOTrack
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation


//Currently not in use
public final class Vector3 {
    private var x: Double
    private var y: Double
    private var z: Double

    public func getX() -> Double {
        return x;
    }

    public func getY() -> Double {
        return y;
    }

    public func getZ() -> Double {
        return z;
    }

    public init(ix: Double, iy: Double, iz: Double) {
        x = ix;
        y = iy;
        z = iz;
    }

    public func set(ix: Double, iy: Double, iz: Double) {
        x = ix;
        y = iy;
        z = iz;
    }

    public func magnitude() -> Double {
        return (x*x+y*y+z*z).squareRoot();
    }

    public func multiply(f: Double) {
        x *= f;
        y *= f;
        z *= f;
    }

    public func normalise() {
        let mag = magnitude();
        x /= mag;
        y /= mag;
        z /= mag;
    }
}
