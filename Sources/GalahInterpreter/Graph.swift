protocol DirectedGraph {
    associatedtype Node: Hashable
    associatedtype Edge: Hashable

    func nodes() -> [Node]
    func outgoingEdges(of node: Node) -> [Edge]
    func endpoints(of edge: Edge) -> (start: Node, end: Node)
}

struct TypeFieldGraph: DirectedGraph {
    typealias Node = CheckedAST.TypeIndex

    struct Edge: Hashable {
        var parent: CheckedAST.TypeIndex
        var field: CheckedAST.Field
    }

    /// The underlying type referred to by a node.
    enum NodeType {
        case builtin(BuiltinType)
        case `struct`(CheckedAST.Struct)
    }

    var builtinTypes: [BuiltinType]
    var structs: [CheckedAST.Struct]

    func nodes() -> [Node] {
        (0..<builtinTypes.count).map(CheckedAST.TypeIndex.builtin)
            + (0..<structs.count).map(CheckedAST.TypeIndex.struct)
    }

    func outgoingEdges(of node: Node) -> [Edge] {
        switch node {
            case .builtin:
                return []
            case let .struct(index):
                return structs[index].fields.map { field in
                    Edge(parent: node, field: field)
                }
        }
    }

    func endpoints(of edge: Edge) -> (start: Node, end: Node) {
        (edge.parent, edge.field.type)
    }

    func ident(of edge: Edge) -> String {
        edge.field.ident
    }

    func ident(of node: Node) -> String {
        switch node {
            case let .builtin(index):
                builtinTypes[index].ident
            case let .struct(index):
                structs[index].ident
        }
    }

    func type(at node: Node) -> NodeType {
        switch node {
            case let .builtin(index):
                .builtin(builtinTypes[index])
            case let .struct(index):
                .struct(structs[index])
        }
    }
}

struct Path<Node, Edge> {
    private(set) var nodes: [Node]
    private(set) var edges: [Edge]

    /// Paths are guaranteed to have a first node.
    var firstNode: Node {
        nodes[0]
    }

    /// Paths are guaranteed to have a last node.
    var lastNode: Node {
        nodes[nodes.count - 1]
    }

    init(startingAt startNode: Node) {
        nodes = [startNode]
        edges = []
    }

    /// Doesn't check that the node is actually the endpoint of the edge.
    mutating func extend(with edge: Edge, to node: Node) {
        edges.append(edge)
        nodes.append(node)
    }

    /// Doesn't check that the node is actually the endpoint of the edge.
    func extended(with edge: Edge, to node: Node) -> Self {
        var path = self
        path.extend(with: edge, to: node)
        return path
    }

    // TODO: Make the assumption self-evident in the type system
    /// Assumes that the path is a cycle.
    func offset(by offset: Int) -> Self {
        var path = self
        path.nodes =
            Array(nodes[offset..<(nodes.count - 1)]) + Array(nodes[0..<offset]) + [nodes[offset]]
        path.edges = Array(edges[offset..<edges.count]) + Array(edges[0..<offset])
        return path
    }
}

extension DirectedGraph {
    func cycles() -> [Path<Node, Edge>] {
        var visitedNodes: Set<Node> = []
        var travelledEdges: Set<Edge> = []
        var queue: [(Node, Path<Node, Edge>)] = []
        var cycles: [Path<Node, Edge>] = []
        for seedNode in nodes() {
            guard !visitedNodes.contains(seedNode) else {
                continue
            }

            queue = [(seedNode, Path(startingAt: seedNode))]

            while !queue.isEmpty {
                let (node, path) = queue.remove(at: 0)
                visitedNodes.insert(node)
                for edge in outgoingEdges(of: node) {
                    guard !travelledEdges.contains(edge) else {
                        continue
                    }

                    let (_, nextNode) = endpoints(of: edge)

                    // Cycle found
                    if let startIndex = path.nodes.firstIndex(of: nextNode) {
                        var cycle = Path<_, Edge>(startingAt: nextNode)
                        for i in (startIndex + 1)..<path.nodes.count {
                            cycle.extend(with: path.edges[i - 1], to: path.nodes[i])
                        }
                        cycle.extend(with: edge, to: nextNode)
                        cycles.append(cycle)
                        continue
                    }

                    queue.append((nextNode, path.extended(with: edge, to: nextNode)))
                    travelledEdges.insert(edge)
                }
            }
        }

        return cycles
    }
}
