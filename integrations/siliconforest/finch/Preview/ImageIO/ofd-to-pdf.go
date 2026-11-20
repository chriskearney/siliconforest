package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/zc310/ofd/pkg/converter"
)

const maxDocumentSize = 128 << 20

type limitedPDF struct {
	target    io.Writer
	remaining int
}

func (w *limitedPDF) Write(data []byte) (int, error) {
	if len(data) > w.remaining {
		return 0, errors.New("converted PDF exceeds the output limit")
	}
	n, err := w.target.Write(data)
	w.remaining -= n
	return n, err
}

func convert(path string) error {
	input, err := os.Open(path)
	if err != nil {
		return err
	}
	defer input.Close()
	info, err := input.Stat()
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() || info.Size() < 1 || info.Size() > maxDocumentSize {
		return errors.New("OFD input must be a nonempty regular file within the size limit")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	return converter.Convert(ctx, "ofd", "pdf", input, &limitedPDF{os.Stdout, maxDocumentSize})
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: sf-ofd-to-pdf file.ofd")
		os.Exit(2)
	}
	timer := time.AfterFunc(20*time.Second, func() { os.Exit(124) })
	defer timer.Stop()
	if err := convert(os.Args[1]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
