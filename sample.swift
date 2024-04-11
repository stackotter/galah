func fibonacci(_ n: Int) -> Int {
    if n == 1 {
        1
    } else if n == 2 {
        1
    } else {
        fibonacci(n - 1) + fibonacci(n - 2)
    }
}

func main() {
    print("The 20th fibonacci number is:")
    print(fibonacci(20))
}

main()
