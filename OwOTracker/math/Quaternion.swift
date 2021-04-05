//
//  Quaternion.swift
//  OwOTracker
//
//  Created by Ferdinand Martini on 04.04.21.
//

import Foundation

public final class Quaternion {
    private var x : Double
    private var y : Double
    private var z : Double
    private var w : Double
    //private float[] matrixs

    public init(q: Quaternion) {
        self.x = q.x
        self.y = q.y
        self.z = q.z
        self.w = q.w
    }
    
    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
    
    public init(axis: Vector3, angle: Double) {
        let s = Double(sin(angle / 2))
        w = Double(cos(angle / 2))
        x = axis.getX() * s
        y = axis.getY() * s
        z = axis.getZ() * s
    }

    public func set(q: Quaternion) {
        //matrixs = null
        x = q.x
        y = q.y
        z = q.z
        w = q.w
    }

    public func norm() -> Double {
        return dot(q: self).squareRoot()
    }

    public func getW()  -> Double {
        return w
    }

    public func getX()  -> Double {
        return x
    }

    public func getY()  -> Double {
        return y
    }

    public func getZ()  -> Double {
        return z
    }

    /**
     * @param axis
     *            rotation axis, unit vector
     * @param angle
     *            the rotation angle
     * @return self
     */
    public func set(axis: Vector3, angle: Double) {
        //matrixs = null
        let s = Double(sin(angle / 2))
        w = Double(cos(angle / 2))
        x = axis.getX() * s
        y = axis.getY() * s
        z = axis.getZ() * s
    }

    public func mul(q: Quaternion) {
        //matrixs = null
        let nw = w * q.w - x * q.x - y * q.y - z * q.z
        let nx = w * q.x + x * q.w + y * q.z - z * q.y
        let ny = w * q.y + y * q.w + z * q.x - x * q.z
        z = w * q.z + z * q.w + x * q.y - y * q.x
        w = nw
        x = nx
        y = ny
    }

    public func scale(scale: Double) {
        if (scale != 1) {
            //matrixs = null
            w *= scale
            x *= scale
            y *= scale
            z *= scale
        }
    }

    public func divs(scale: Double) {
        if (scale != 1) {
            //matrixs = null
            w /= scale
            x /= scale
            y /= scale
            z /= scale
        }
    }

    public func dot(q: Quaternion) -> Double {
        return x * q.x + y * q.y + z * q.z + w * q.w
    }

    public func equals(q: Quaternion) -> Bool {
        return x == q.x && y == q.y && z == q.z && w == q.w
    }

    public func interpolateself(q: Quaternion, t: Double) {
        if (!equals(q: q)) {
            var d = dot(q: q)
            var qx, qy, qz, qw : Double

            if (d < 0) {
                qx = -q.x
                qy = -q.y
                qz = -q.z
                qw = -q.w
                d = -d
            } else {
                qx = q.x
                qy = q.y
                qz = q.z
                qw = q.w
            }

            var f0, f1 : Double

            if ((1 - d) > 0.1) {
                let angle = Double(acos(d))
                let s = Double(sin(angle))
                let tAngle = t * angle
                f0 = Double(sin(angle - tAngle) / s)
                f1 = Double(sin(tAngle) / s)
            } else {
                f0 = 1 - t
                f1 = t
            }

            x = f0 * x + f1 * qx
            y = f0 * y + f1 * qy
            z = f0 * z + f1 * qz
            w = f0 * w + f1 * qw
        }
    }

    public func normalizeThis() {
        divs(scale: norm())
    }

    public func interpolate(q: Quaternion, t: Double) -> Quaternion {
        let quat = Quaternion(q: self)
        quat.interpolateself(q: q, t: t)
        return quat
    }

    /**
     * Converts self Quaternion into a matrix, placing the values into the given array.
     * @param matrixs 16-length float array.
     */
    public final func toMatrix() {
        var matrixs = [Float].init(repeating: 0.0, count: 16)
        matrixs[3] = 0.0
        matrixs[7] = 0.0
        matrixs[11] = 0.0
        matrixs[12] = 0.0
        matrixs[13] = 0.0
        matrixs[14] = 0.0
        matrixs[15] = 1.0

        matrixs[0] = Float((1.0 - (2.0 * ((y * y) + (z * z)))))
        matrixs[1] = Float((2.0 * ((x * y) - (z * w))))
        matrixs[2] = Float((2.0 * ((x * z) + (y * w))))

        matrixs[4] = Float((2.0 * ((x * y) + (z * w))))
        matrixs[5] = Float((1.0 - (2.0 * ((x * x) + (z * z)))))
        matrixs[6] = Float((2.0 * ((y * z) - (x * w))))

        matrixs[8] = Float((2.0 * ((x * z) - (y * w))))
        matrixs[9] = Float((2.0 * ((y * z) + (x * w))))
        matrixs[10] = Float((1.0 - (2.0 * ((x * x) + (y * y)))))
    }


    public static func createFromAxisAngle(xx: Float, yy: Float, zz: Float, a: Float) -> Quaternion {
        // Here we calculate the sin( theta / 2) once for optimization
        let factor = Float(sin( a / 2.0 ))

        // Calculate the x, y and z of the quaternion
        let x = Double(xx * factor)
        let y = Double(yy * factor)
        let z = Double(zz * factor)

        // Calcualte the w value by cos( theta / 2 )
        let w = Double(cos( a / 2.0 ))

        let quat = Quaternion(x: x, y: y, z: z, w: w)
        quat.normalizeThis()
        return quat
    }

}
