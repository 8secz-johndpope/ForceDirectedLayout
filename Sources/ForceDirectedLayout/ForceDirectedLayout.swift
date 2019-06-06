///  Copyright © 2019 Nicolas Zinovieff. All rights reserved.
///  Licence : MIT

import UIKit

extension UIView {
    var absoluteCenter : CGPoint {
        return CGPoint(x: self.frame.width*0.5, y: self.frame.height*0.5)
    }
}

protocol ForceDirectedLayoutDelegate {
    func layoutDidFinish()
}
class ForceDirectedLayout : UICollectionViewLayout {
    /// in case you want to know
    var delegate : ForceDirectedLayoutDelegate? = nil
    
    // maths
    var springStiffness : CGFloat = 0.02 // max(width,height)/1000 seems ok
    var electricCharge : CGFloat = 10 // max(width,height)/2 seems ok
    var cellSize : CGSize = CGSize(width: 20,height: 20) // obviously too small for real use
    
    /// Holds the components a generic force, to be computed from the other laws. Used mostly for summing all the forces
    struct Force {
        /// The x component
        let dx: CGFloat
        /// The y component
        let dy: CGFloat
        
        
        /// Adds two forces together
        /// - Parameter lhs: a force
        /// - Parameter rhs: another force
        static func +(lhs: Force, rhs: Force) -> Force {
            return Force(lhs.dx+rhs.dx,lhs.dy+rhs.dy)
        }
        
        /// Modulates a force
        /// - Parameter lhs: a force
        /// - Parameter rhs: the modulation factor
        static func /(lhs: Force, rhs: CGFloat) -> Force {
            return Force(lhs.dx/rhs, lhs.dy/rhs)
        }
        
        /// Standard init, all variables
        init(_ x: CGFloat, _ y: CGFloat) {
            dx = x
            dy = y
        }
        
        /// Helper for the angle in the plane
        var angle : CGFloat {
            return CGFloat(atan2(Double(dy), Double(dx)))
        }
        
        /// Helper for the magnitude
        var magnitude : CGFloat {
            return sqrt(dx*dx+dy*dy)
        }
    }
    
    /// Structure that represents our cell in our "physical" universe
    struct Node : Equatable, Hashable {
        /// the x position in the screen plane
        var x : CGFloat = 0
        /// the y position in the screen plane
        var y : CGFloat = 0
        
        /// for identification purposes
        let uuid = UUID()
        /// because we use it for a collection view
        var indexPath : IndexPath
        
        /// standard initializer
        init(x px: CGFloat = 0, y py: CGFloat = 0, for idx: IndexPath) {
            x = px
            y = py
            indexPath = idx
        }
        
        /// Equality check
        /// - Parameter lhs: a node
        /// - Parameter rhs: another node
        static func == (lhs: Node, rhs: Node) -> Bool {
            return lhs.uuid == rhs.uuid
        }
        
        /// Calculates the attraction force to a point
        /// - Parameter center: the point of attraction
        /// - Parameter stiffness: the stiffness of the spring attaching the node to the center
        func attraction(center: CGPoint, stiffness: CGFloat) -> Force {
            // Hooke's Law: F = -k•∂ (∂ being the "ideal" distance minus the actual distance)
            let dx = x - center.x
            let dy = y - center.y
            let angle = CGFloat(atan2(Double(dy), Double(dx)))
            let delta = sqrt(dx*dx+dy*dy)
            let intensity = stiffness * delta
            let ix = abs(intensity * cos(angle))
            let fx : CGFloat
            if center.x > x { // positive force to the right
                fx = ix
            } else {
                fx = -ix
            }
            let iy = abs(intensity * sin(angle))
            let fy : CGFloat
            if center.y > y { // positive force to the bottom
                fy = iy
            } else {
                fy = -iy
            }
            return Force(fx,fy)
        }
        
        /// Calculates the repulsion force to other nodes
        /// - Parameter others: all the nodes we are repulsed by
        /// - Parameter charge: the "electric charge" of the nodes. No relation to actual physical values
        func repulsion(others: [Node], charge: CGFloat) -> Force {
            var totalForce = Force(0,0)
            for n in others.filter({ (on) -> Bool in
                on.uuid != self.uuid // just in case
            }) {
                // Coulomb’s Law; F = k(Q1•Q2/r²)
                // Since we're dealing with arbitrary "charges" here, we'll simplify to F = C³/r²
                // We want repulsion (Q1=Q2) and not deal with big numbers, so that works
                var dx = x - n.x
                var dy = y - n.y
                if dx == 0 && dy == 0 { // wiggle a bit
                    let room : CGFloat = 0.05
                    dx += CGFloat.random(in: -room...room)
                    dy += CGFloat.random(in: -room...room)
                }
                let angle = CGFloat(atan2(Double(dy), Double(dx)))
                let delta = max(0.000001,sqrt(dx*dx+dy*dy)) // do NOT divide by zero you fool
                let intensity = pow(charge,3)/(delta*delta)
                let ix = abs(intensity * cos(angle))
                let fx : CGFloat
                if n.x > x { // positive force to the left
                    fx = -ix
                } else {
                    fx = ix
                }
                let fy : CGFloat
                let iy = abs(intensity * sin(angle))
                if n.y > y { // positive force to the bottom
                    fy = -iy
                } else {
                    fy = iy
                }
                
                totalForce = totalForce + Force(fx,fy)
            }
            
            return totalForce
        }
        
        /// Computes the global force exerted on this node
        /// - Parameter center: center of attraction
        /// - Parameter otherNodes: all the other nodes to be repulsed by
        /// - Parameter stiffness: the stiffness of the spring
        /// - Parameter charge: the "electric charge" of the nodes. No relation to actual physical values
        func globalForce(center: CGPoint, otherNodes: [Node], stiffness: CGFloat, charge: CGFloat) -> Force {
            let a = attraction(center: center, stiffness: stiffness)
            let r = repulsion(others: otherNodes, charge: charge)
            return a + r
        }
        
        /// Applies a force to a node
        /// - Parameter lhs: the node
        /// - Parameter rhs: the force
        static func +(lhs: Node, rhs: Force) -> Node {
            return Node(x: lhs.x+rhs.dx, y: lhs.y+rhs.dy, for: lhs.indexPath)
        }
    }
    
    /// Takes a
    /// - Parameter center: the point of attraction
    /// - Parameter nodes: the current nodes
    func computeNewPositions(center: CGPoint, nodes: [Node]) -> (nodes: [Node], movement: CGFloat) {
        // if the total movement is less than threshold, will return nil
        var totalMovement : CGFloat = 0
        var newNodes : [Node] = []
        var computeTasks : [Task] = []
        let lock = NSLock()
        for n in nodes {
            let t = Task() {
                let f = n.globalForce(center: center, otherNodes: nodes, stiffness: self.springStiffness, charge: self.electricCharge)
                let nn = n + f
                lock.lock()
                newNodes.append(nn)
                totalMovement += f.magnitude
                lock.unlock()
            }
            computeTasks.append(t)
        }
        let waitSem = DispatchSemaphore(value: 0)
        let compute = Task.group(computeTasks)
        compute.perform { (outcome) in
            waitSem.signal()
        }
        waitSem.wait()
        
        return (newNodes, totalMovement)
    }
    
    
    /// Collection view content size depends on the position of all the cells
    override var collectionViewContentSize: CGSize {
        var totalRect = CGRect(origin: CGPoint.zero, size: self.collectionView?.frame.size ?? CGSize.zero)
        for cachedA in cachedAttributes.values {
            totalRect = totalRect.union(
                CGRect(x: cachedA.center.x-cachedA.size.width*0.5,
                       y: cachedA.center.y-cachedA.size.height*0.5,
                       width: cachedA.size.width, height: cachedA.size.height))
        }
        return totalRect.size
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true // because the center changes...
    }
    
    // For debug purposes, if needed
    fileprivate var speedLock = NSLock()
    var speeds = [CGFloat]()
    var avererageSpeed : CGFloat {
        speedLock.lock()
        while speeds.count > 5 { // averaged over 5
            speeds.remove(at: 0)
        }
        if speeds.count == 0 {
            speedLock.unlock()
            return 0
        }
        var sum : CGFloat = 0
        for s in speeds { sum += s }
        let result = sum / CGFloat(speeds.count) // can't be zero
        speedLock.unlock()
        return result
    }
    var averageDelta : CGFloat {
        speedLock.lock()
        if speeds.count < 2 {
            speedLock.unlock()
            return 0
        }
        var result : CGFloat = 0
        for i in 1..<speeds.count {
            result += (speeds[i]-speeds[i-i])
        }
        result /= CGFloat(speeds.count-1)
        speedLock.unlock()
        return result
    }
    func recordSpeed(_ s: CGFloat) {
        speedLock.lock()
        speeds.append(s)
        speedLock.unlock()
    }
    
    /// Unfortunately, collectionView.layoutAttributesForItem doesn't seem to be caching the previous attributes
    /// We do it ourselves as a backup
    fileprivate var cachedAttributes = [IndexPath:UICollectionViewLayoutAttributes]()

    /// Since we cache the data ourselves, we need to cleanup if elements are removed
    override func prepare() {
        super.prepare()
        
        guard let collection = self.collectionView else {
            cachedAttributes.removeAll()
            return
        }
        let sectionCount = collection.dataSource?.numberOfSections?(in: collection) ?? 1
        var rowCounts = [Int:Int]()
        for s in 0..<sectionCount {
            rowCounts[s] = collection.dataSource?.collectionView(collection, numberOfItemsInSection: s) ?? 0
        }
        for removed in cachedAttributes.keys.filter({ (idx) -> Bool in
            return idx.section >= sectionCount || idx.row >= (rowCounts[idx.section] ?? 0) // hence the dictionary, no index out of bounds
        }) {
            cachedAttributes.removeValue(forKey: removed)
        }
    }
    
    /// Unfortunately, every node affects every other node, so we can't do partial updates
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attributes : [UICollectionViewLayoutAttributes] = []
        var nodes = [Node]()
        
        if let collectionView = self.collectionView {
            for i in 0..<(collectionView.dataSource?.collectionView(collectionView, numberOfItemsInSection: 0) ?? 0) {
                let idx = IndexPath(row: i, section: 0)
                let currentAttributes : UICollectionViewLayoutAttributes
                if let ca = (collectionView.layoutAttributesForItem(at: idx) ?? cachedAttributes[idx]) {
                    currentAttributes = ca
                } else {
                    // randomize start positions, just for funsies
                    currentAttributes = UICollectionViewLayoutAttributes(forCellWith: idx)
                    currentAttributes.center = CGPoint(
                        x: CGFloat.random(in: 0...self.collectionViewContentSize.width),
                        y: CGFloat.random(in: 0...self.collectionViewContentSize.height)
                    )
                    currentAttributes.size = cellSize
                    cachedAttributes[idx] = currentAttributes
                }
                attributes.append(currentAttributes)
                nodes.append(Node(x: currentAttributes.center.x, y: currentAttributes.center.y, for: idx))
            }
            
            let center = self.collectionView?.absoluteCenter ?? CGPoint.zero
            let nextIteration : (nodes: [Node], movement: CGFloat)
            nextIteration = computeNewPositions(
                center: center,
                nodes: nodes)
            
            for n in nextIteration.nodes {
                if let attrsIdx = attributes.firstIndex(where: { $0.indexPath == n.indexPath }) {
                    let attrs = attributes[attrsIdx]
                    attrs.center = CGPoint(x: n.x, y: n.y)
                    attributes[attrsIdx] = attrs
                }
            }
            
            // debug
            recordSpeed(nextIteration.movement)
            print("Going at roughly \(avererageSpeed)px/s on average")
            
            // if it's still moving, keep going
            if nextIteration.movement > 0.3 { // subpixel animation
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.05) {
                    self.invalidateLayout()
                }
            } else {
                DispatchQueue.main.async {
                    self.delegate?.layoutDidFinish()
                }
            }
            
        }
        
        return attributes
    }
}

